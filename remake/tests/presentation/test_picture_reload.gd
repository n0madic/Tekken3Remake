extends TestSuite
## The pictures a 2D view takes from TexturePacks when it is set up follow a texture pack chosen
## later (`reload_pictures`), and a tap waiting while the settings are open does not reach the game
## once they close.

const PACKS := "user://test_picture_reload"
const PACK := "test"
const SCREENS := "res://imported/screens"


func test_options_pictures_follow_the_pack() -> void:
	var picture := SCREENS.path_join("options.png")
	if not require(TexturePacks.INDEX) or not require(picture + ".import"):
		return
	var key := TexturePacks.key_of(picture)
	if not expect(not key.is_empty(), "the options picture is replaceable"):
		return
	var saved_dir := TexturePacks.directory
	var saved_pack: Variant = Settings.values.get("texture_pack")
	TexturePacks.directory = PACKS
	Settings.values["texture_pack"] = ""
	TexturePacks.clear()
	var view := OptionsView.new()
	view.setup(null, null, VramImage.new(), SCREENS)
	var original := view.picture_texture
	expect(original != null and not original is ImageTexture, "no pack: the converted picture")

	var dir := PACKS.path_join(PACK)
	DirAccess.make_dir_recursive_absolute(dir)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png(dir.path_join(key + ".png"))
	var f := FileAccess.open(dir.path_join(TexturePacks.MANIFEST), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	Settings.values["texture_pack"] = PACK
	TexturePacks.clear()
	view.reload_pictures()
	expect(view.picture_texture is ImageTexture, "the pack's replacement once reloaded")
	expect_equal(view.picture_texture.get_size(), original.get_size(), "at the original's size")

	view.free()
	TexturePacks.directory = saved_dir
	if saved_pack == null:
		Settings.values.erase("texture_pack")
	else:
		Settings.values["texture_pack"] = saved_pack
	TexturePacks.clear()
	_remove(PACKS)


func test_tap_does_not_outlive_the_settings() -> void:
	var saved_card: Variant = Settings.values.get("memory_card")
	Settings.values["memory_card"] = 1          # the same card: closing does not switch it
	var game := (load("res://app/game.gd") as GDScript).new() as Node
	game.set("_tap", true)
	game.call("_on_settings_closed")
	expect_equal(game.get("_tap"), false, "the tap is dropped as the settings close")
	game.free()
	Settings.values["memory_card"] = saved_card


func _remove(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove(path.path_join(sub))
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(path)
