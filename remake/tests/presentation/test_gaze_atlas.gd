extends TestSuite
## Gon's eyes' look direction on his atlas (GazeAtlas, FighterView.set_gaze; the patches are
## tools/remake_import/gaze.py's, which tools/research/gon_eyes_cases.py and tests/core/test_gon_eyes.gd
## check against the game).

const DIR := "res://imported"
const TEXTURE := "icon.png"
const SHEET := "icon_background.png"
const NO := GazeAtlas.NO_SHIFT
const RED := Color(1, 0, 0, 1)
const GREEN := Color(0, 1, 0, 1)
const GREY := Color8(128, 128, 128)
const BLACK := Color(0, 0, 0, 1)


func _image(size: int, colour: Color) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return image


## A 16 × 16 atlas (a 1024 × 8 sheet): eye 0 has the rectangle (2, 2, 4, 4) with shift 3 at sheet
## x 0 and shift 4 at x 8, eye 1 (10, 10, 4, 4) with shift −2 at x 16; the swapped palette has
## eye 1's rectangle only.
func _atlas(scale: int = 1) -> GazeAtlas:
	var sheet := Image.create(1024 * scale, 8 * scale, false, Image.FORMAT_RGBA8)
	sheet.fill_rect(Rect2i(0, 0, 4 * scale, 4 * scale), RED)
	sheet.fill_rect(Rect2i(8 * scale, 0, 4 * scale, 4 * scale), GREEN)
	sheet.fill_rect(Rect2i(16 * scale, 0, 4 * scale, 4 * scale), BLACK)
	var data := {"size": [16, 16], "sheet": "x.png", "patches": {
		"0": {"0": {"rects": [[2, 2, 4, 4]], "shifts": {"3": [[0, 0]], "4": [[8, 0]]}},
			"1": {"rects": [[10, 10, 4, 4]], "shifts": {"-2": [[16, 0]]}}},
		"1": {"1": {"rects": [[10, 10, 4, 4]], "shifts": {"-2": [[16, 0]]}}},
	}}
	return GazeAtlas.new(data, ImageTexture.create_from_image(_image(16 * scale, GREY)),
			ImageTexture.create_from_image(_image(16 * scale, Color.WHITE)), ImageTexture.create_from_image(sheet))


func _pixel(atlas: GazeAtlas, x: int, y: int) -> Color:
	return atlas.image().get_pixel(x, y)


func test_the_patches_are_pasted_over_the_atlas() -> void:
	var atlas := _atlas()
	atlas.show(false, PackedInt32Array([NO, NO]))
	expect_equal(_pixel(atlas, 3, 3), GREY, "as loaded")
	atlas.show(false, PackedInt32Array([3, NO]))
	expect_equal(_pixel(atlas, 3, 3), RED, "eye 0's shift 3")
	expect_equal(_pixel(atlas, 1, 1), GREY, "outside the rectangle")
	expect_equal(_pixel(atlas, 11, 11), GREY, "the other eye is as loaded")
	atlas.show(false, PackedInt32Array([4, -2]))
	expect_equal(_pixel(atlas, 3, 3), GREEN, "eye 0's shift 4")
	expect_equal(_pixel(atlas, 11, 11), BLACK, "eye 1's shift −2")
	atlas.show(false, PackedInt32Array([NO, -2]))
	expect_equal(_pixel(atlas, 3, 3), GREY, "an eye back to as loaded")
	expect_equal(_pixel(atlas, 11, 11), BLACK, "the other stays")


func test_the_swapped_palette_has_its_own_atlas_and_patches() -> void:
	var atlas := _atlas()
	atlas.show(false, PackedInt32Array([3, -2]))
	atlas.show(true, PackedInt32Array([3, -2]))
	expect_equal(_pixel(atlas, 3, 3), Color.WHITE, "the swapped atlas has no patches for eye 0")
	expect_equal(_pixel(atlas, 11, 11), BLACK, "but one for eye 1")
	atlas.show(false, PackedInt32Array([3, -2]))
	expect_equal(_pixel(atlas, 3, 3), RED, "and back")


## A pack that replaces the atlas as loaded (here 2x) and not the swapped one: the texture keeps one size.
func test_atlases_of_different_sizes_follow_the_first() -> void:
	var sheet := Image.create(1024, 8, false, Image.FORMAT_RGBA8)
	sheet.fill_rect(Rect2i(0, 0, 4, 4), RED)
	var data := {"size": [16, 16], "sheet": "x.png", "patches": {
		"0": {"0": {"rects": [[2, 2, 4, 4]], "shifts": {"3": [[0, 0]]}}}}}
	var atlas := GazeAtlas.new(data, ImageTexture.create_from_image(_image(32, GREY)),
			ImageTexture.create_from_image(_image(16, Color.WHITE)), ImageTexture.create_from_image(sheet))
	atlas.show(true, PackedInt32Array([GazeAtlas.NO_SHIFT, GazeAtlas.NO_SHIFT]))
	expect_equal(atlas.image().get_size(), Vector2i(32, 32), "the swapped atlas is scaled to the first")
	expect_equal(_pixel(atlas, 20, 20), Color.WHITE, "and keeps its picture")
	atlas.show(false, PackedInt32Array([3, GazeAtlas.NO_SHIFT]))
	expect_equal(atlas.image().get_size(), Vector2i(32, 32), "the same size again")
	expect_equal(_pixel(atlas, 5, 5), RED, "with the patch scaled to it")


func test_the_patches_follow_a_larger_atlas() -> void:
	var atlas := _atlas(2)
	atlas.show(false, PackedInt32Array([3, NO]))
	expect_equal(atlas.image().get_width(), 32, "the pack's size")
	expect_equal(_pixel(atlas, 4, 4), RED, "the patch scaled to it")
	expect_equal(_pixel(atlas, 11, 11), RED, "its far corner")
	expect_equal(_pixel(atlas, 12, 12), GREY, "and no more")


## FighterView.set_gaze copies a strip only when its shift differs from the last one copied.
func test_an_eye_copies_when_its_shift_changes() -> void:
	if not require(DIR.path_join(TEXTURE)):
		return
	var model := CharacterModel.new()
	model.directory = DIR
	model.texture = TEXTURE
	model.swap_texture = TEXTURE
	model.gaze = {"size": [16, 16], "sheet": SHEET, "patches": {}}
	var view := FighterView.new()
	view.setup(model)
	expect(view.gaze_atlas != null, "the model has the atlas")
	var cases := [
		[0, [NO, NO], "looking straight: nothing is copied"],
		[5, [5, NO], "eye 0 takes the shift, eye 1's 0 is what it had"],
		[5, [5, NO], "the same again"],
		[-3, [0, -3], "the other side: eye 0 is copied back to 0"],
		[0, [0, 0], "eye 1 back to 0 as well"],
		[7, [7, 0], "and eye 0 again"],
	]
	for c: Array in cases:
		view.set_gaze(c[0] as int)
		expect_equal(view._gaze_shifts, PackedInt32Array(c[1] as Array), "%d: %s" % [c[0], c[2]])
	view.free()


func test_converted_gon() -> void:
	for slot: int in [42, 43]:
		var dir := AssetCatalog.ROOT.path_join("characters/costume_%02d" % slot)
		if not require(dir.path_join("model.json")):
			return
		var model := CharacterModel.new()
		model = CharacterModel.load_from(dir)
		if model.gaze.is_empty():
			skip("costume %d was converted before the eyes' look direction" % slot)
			return
		expect(FileAccess.file_exists(dir.path_join(model.gaze["sheet"] as String)), "slot %d: the sheet" % slot)
		var patches: Dictionary = model.gaze["patches"]
		expect(patches.has("0") and (patches["0"] as Dictionary).has("0") and (patches["0"] as Dictionary).has("1"),
				"slot %d: both eyes in the palette as loaded" % slot)
		var eye0: Dictionary = (patches["0"] as Dictionary)["0"]
		expect_equal((eye0["shifts"] as Dictionary).size(), 18, "slot %d: eye 0's shifts 0 to 17" % slot)
		var eye1: Dictionary = (patches["0"] as Dictionary)["1"]
		expect((eye1["shifts"] as Dictionary).has("-17") and (eye1["shifts"] as Dictionary).has("0"),
				"slot %d: eye 1's shifts −17 to 0" % slot)
	for slot: int in [0, 22, 44]:
		var dir := AssetCatalog.ROOT.path_join("characters/costume_%02d" % slot)
		if FileAccess.file_exists(dir.path_join("model.json")):
			expect(CharacterModel.load_from(dir).gaze.is_empty(), "slot %d has no look direction" % slot)
