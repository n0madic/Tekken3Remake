extends TestSuite
## What the 2D views read from the converted pictures: the fight HUD's name plates go by the
## costume key (a slot can serve two characters' costumes), and GAME OPTION's mode pictures are in
## the options' own VRAM, not the system image the other screens start from.

const HUD_JSON := "res://imported/hud/hud.json"
const SCREENS := "res://imported/screens"
const ANNA_FIRST := 72
const ANNA_THIRD := 74
const NINA_THIRD := 22
const MODE_PICTURES := Vector2i(704, 0)
const MODE_PICTURE_LINES := 112


func _entry(data: HudData, key: int) -> Dictionary:
	return data.names[str(key)]


func test_a_shared_slot_keeps_each_costumes_colours() -> void:
	if not require(HUD_JSON):
		return
	var data := HudData.load_from(HUD_JSON.get_base_dir())
	expect_equal(_entry(data, ANNA_FIRST)["plate"], "plate_0.png", "Anna's first costume: the first plate")
	expect_equal(_entry(data, NINA_THIRD)["plate"], "plate_2.png", "Nina's third, on the same slot: the third")
	expect_equal(_entry(data, ANNA_THIRD)["plate"], "plate_2.png", "Anna's third: the third")
	expect(str(_entry(data, ANNA_FIRST)["file"]) != str(_entry(data, NINA_THIRD)["file"]), "each with its own name sprite")


func _lit_words(image: VramImage) -> int:
	var lit := 0
	for y in MODE_PICTURE_LINES:
		for x in 24:
			if image.word(MODE_PICTURES.x + x, MODE_PICTURES.y + y) != 0:
				lit += 1
	return lit


func test_the_options_vram_has_the_mode_pictures() -> void:
	var system_file := SCREENS.path_join("vram_system.bin")
	if not require(system_file) or not require(SCREENS.path_join("options.tims")) or not require(SCREENS.path_join("options.png") + ".import"):
		return
	var system := VramImage.load_system(system_file)
	var view := OptionsView.new()
	view.setup(null, null, system, SCREENS)
	expect(_lit_words(view.vram) > 0, "the pictures are uploaded")
	expect_equal(_lit_words(system), 0, "the shared system image is left alone")
	view.free()
