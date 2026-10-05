extends TestSuite
## A texture pack's VRAM replacements (TexturePacks.vram_sprite through VramImage): a sprite
## inside a replaced rectangle is cut from the replacement at its scale and keeps its size, only
## through the CLUT colours the replacement was made for and while the VRAM holds the words it
## replaces. The pack is written to a folder of the tests' own.

const PACKS := "user://test_texture_packs"   ## each test writes its own folder, PACKS + a suffix (the runners share user://)

var _packs := PACKS
const PACK := "test"
const PAGE := Vector2i(64, 0)            ## tpage 1: VRAM word (64, 0), 4-bit
const RECT := Rect2i(16, 8, 8, 4)        ## texels of the page
const CLUT := Vector2i(0, 480)
const SCALE := 2
const RED := Color(1, 0, 0)


func test_replaced_sprites() -> void:
	_packs = PACKS + "_replaced"
	var saved_dir := TexturePacks.directory
	var saved_pack: Variant = Settings.values.get("texture_pack")
	TexturePacks.directory = _packs
	Settings.values["texture_pack"] = PACK
	TexturePacks.clear()
	var vram := _vram()
	_write_pack(vram)
	var tpage := PAGE.x / 64
	var clut := (CLUT.y << 6) | (CLUT.x / 16)

	var whole := vram.sprite(RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y, clut, tpage)
	expect_equal(whole.get_size(), Vector2(RECT.size), "a replaced sprite keeps its size")
	expect_equal(whole.get_image().get_size(), RECT.size * SCALE, "and holds the replacement's texels")
	expect_equal(whole.get_image().get_pixel(0, 0), RED, "cut from the replacement")
	var part := vram.sprite(RECT.position.x + 2, RECT.position.y + 1, 4, 2, clut, tpage)
	expect_equal(part.get_image().get_size(), Vector2i(4, 2) * SCALE, "a sprite inside the rectangle is cut from it")
	var other := vram.sprite(RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y, clut + 1, tpage)
	expect_equal(other.get_image().get_size(), RECT.size, "another CLUT's colours: the VRAM's own texels")
	var outside := vram.sprite(RECT.position.x + 4, RECT.position.y, RECT.size.x, RECT.size.y, clut, tpage)
	expect_equal(outside.get_image().get_size(), RECT.size, "a sprite leaving the rectangle is not replaced")

	# Other words in the rectangle (another picture uploaded there): the VRAM's own texels.
	var tim := _tim(PAGE.x + RECT.position.x / 4, PAGE.y + RECT.position.y, 0x2222)
	vram.upload_tim(tim)
	var changed := vram.sprite(RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y, clut, tpage)
	expect_equal(changed.get_image().get_size(), RECT.size, "changed VRAM words are not replaced")

	Settings.values["texture_pack"] = ""
	TexturePacks.clear()
	var none := _vram().sprite(RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y, clut, tpage)
	expect_equal(none.get_image().get_size(), RECT.size, "no pack: the VRAM's own texels")

	TexturePacks.directory = saved_dir
	if saved_pack == null:
		Settings.values.erase("texture_pack")
	else:
		Settings.values["texture_pack"] = saved_pack
	TexturePacks.clear()
	_remove(_packs)


## A user's vram.json is not trusted: malformed entries are skipped, and a replacement smaller
## than its rectangle at its scale replaces nothing.
func test_malformed_vram_index() -> void:
	_packs = PACKS + "_malformed"
	var saved_dir := TexturePacks.directory
	var saved_pack: Variant = Settings.values.get("texture_pack")
	TexturePacks.directory = _packs
	Settings.values["texture_pack"] = PACK
	TexturePacks.clear()
	var vram := _vram()
	_write_pack(vram)
	var tpage := PAGE.x / 64
	var clut := (CLUT.y << 6) | (CLUT.x / 16)
	var index := _packs.path_join(PACK).path_join(TexturePacks.VRAM_INDEX)
	for text: String in ["", "{\"entries\": [,]}", "[]", "{\"entries\": 3}", "{\"entries\": [{\"page\": [64, 0]}, 7]}",
			"{\"entries\": [{\"page\": [64, 0], \"depth\": 4, \"rect\": [0, 0, 300, 4], \"palette\": [], \"scale\": 1, \"file\": \"vram/a.png\", \"check\": \"\"}]}",
			"{\"entries\": [{\"page\": [64, 0], \"depth\": 4, \"rect\": [0, 0, 8, 4], \"palette\": [], \"scale\": 1, \"file\": \"../../x.png\", \"check\": \"\"}]}",
			"{\"entries\": [{\"page\": [64, 0], \"depth\": 4, \"rect\": [0, 0, 8, 4], \"palette\": [], \"scale\": 1, \"file\": \"/etc/x.png\", \"check\": \"\"}]}"]:
		var f := FileAccess.open(index, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		TexturePacks.clear()
		expect_equal(TexturePacks._vram_entries(PACK, "64,0,4").size(), 0, "nothing taken from %s" % text)
		var sprite := vram.sprite(RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y, clut, tpage)
		expect_equal(sprite.get_image().get_size(), RECT.size, "the VRAM's own texels")
	# A replacement picture smaller than the rectangle at its scale.
	_write_pack(vram)
	var small := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	small.save_png(_packs.path_join(PACK).path_join("vram/a.png"))
	TexturePacks.clear()
	var cut := vram.sprite(RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y, clut, tpage)
	expect_equal(cut.get_image().get_size(), RECT.size, "a short replacement replaces nothing")
	TexturePacks.directory = saved_dir
	if saved_pack == null:
		Settings.values.erase("texture_pack")
	else:
		Settings.values["texture_pack"] = saved_pack
	TexturePacks.clear()
	_remove(_packs)


## A VRAM with texels 1 in the page and two colours at CLUT, another two at the next CLUT.
func _vram() -> VramImage:
	var v := VramImage.new()
	v.words.resize(VramImage.WIDTH * VramImage.HEIGHT * 2)
	for y in 256:
		for x in 64:
			v.words.encode_u16(2 * ((PAGE.y + y) * VramImage.WIDTH + PAGE.x + x), 0x1111)
	for i in 4:
		v.words.encode_u16(2 * (CLUT.y * VramImage.WIDTH + CLUT.x + i), 0x7C00 + i)
	for i in 2:
		v.words.encode_u16(2 * (CLUT.y * VramImage.WIDTH + CLUT.x + 16 + i), 0x03E0 + i)
	return v


## A 4-bit TIM without a CLUT: 2 × 4 words of `word` at (x, y).
func _tim(x: int, y: int, word: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(8 + 12 + 16)
	t.encode_u32(0, 0x10)
	t.encode_u32(4, 0)
	t.encode_u32(8, 12 + 16)
	t.encode_u16(12, x)
	t.encode_u16(14, y)
	t.encode_u16(16, 2)
	t.encode_u16(18, 4)
	for i in 8:
		t.encode_u16(20 + 2 * i, word)
	return t


func _write_pack(vram: VramImage) -> void:
	var dir := _packs.path_join(PACK)
	DirAccess.make_dir_recursive_absolute(dir.path_join("vram"))
	var image := Image.create(RECT.size.x * SCALE, RECT.size.y * SCALE, false, Image.FORMAT_RGBA8)
	image.fill(RED)
	image.save_png(dir.path_join("vram/a.png"))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for row in RECT.size.y:
		var at := 2 * ((PAGE.y + RECT.position.y + row) * VramImage.WIDTH + PAGE.x + RECT.position.x / 4)
		ctx.update(vram.words.slice(at, at + 2 * RECT.size.x / 4))
	var entry := {"page": [PAGE.x, PAGE.y], "depth": 4, "rect": [RECT.position.x, RECT.position.y, RECT.size.x, RECT.size.y],
		"palette": [0x7C00, 0x7C01], "scale": SCALE, "file": "vram/a.png", "check": ctx.finish().hex_encode()}
	var f := FileAccess.open(dir.path_join(TexturePacks.VRAM_INDEX), FileAccess.WRITE)
	f.store_string(JSON.stringify({"entries": [entry]}))
	f.close()
	f = FileAccess.open(dir.path_join(TexturePacks.MANIFEST), FileAccess.WRITE)
	f.store_string("{}")
	f.close()


func _remove(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove(path.path_join(sub))
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(path)
