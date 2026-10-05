extends TestSuite
## The arcade models' hand and jaw variants (FUN_80194458, arcade/README.md#true-ogres-wings-and-the-variant-selection):
## ArcadePoses selects variant `value >> 4` (a blend step, 0–32) or `value − 0x1E0` (a shape,
## 33–40) of the channel's current value, the converter's packed groups load as one set of surfaces
## patched with the pose tables, and FighterView shows an arcade model's hands by those numbers (the
## PlayStation's by FighterHands.variant, also for the jaw of its Kuma, Panda and Gon: packed, ten
## variants). tools/research/verify_arcade_wings.py and tools/research/verify_hand_poses.py check the selections
## against the routines in the CPU harness.

const STRIDE := 28
const VARIANTS := 41
const DIR := "user://test_arcade_hands"
const TEXTURE_DIR := "res://imported"
const TEXTURE := "icon.png"
const SWAP_TEXTURE := "icon_background.png"
const FIST_VARIANT := 32
const SHAPE_VARIANTS := 8                    ## variants 33–40
const JAW_SLOTS := [22, 23]
const PS1_JAW_SLOTS := [42, 43]              ## Gon: only the PlayStation's model has him
const PS1_VARIANTS := 10                     ## the PlayStation's channel values 0..0x206


func test_the_arcades_numbers_of_a_channel_value() -> void:
	var expected := {
		0: 0, 1: 0, 15: 0, 16: 1, 0x7F: 7, 0x80: 8, 0x1FF: 31, 0x200: FIST_VARIANT,
		0x201: 33, 0x202: 34, 0x206: 38, 0x207: 39, 0x208: 40,
	}
	for value: int in expected:
		expect_equal(ArcadePoses.hand_variant(value), expected[value], "value 0x%X" % value)


func test_a_closing_fist_steps_through_the_blend() -> void:
	var hands := FighterHands.new()
	hands.command(3, 1, 10)      # shape 1, the fist, over 11 steps
	var last := 0
	var seen := {}
	for step in 20:
		hands.update()
		var v := ArcadePoses.hand_variants(hands)
		expect_equal(v[0], v[1], "both hands close together")
		expect(v[0] >= last, "the blend only closes")
		last = v[0]
		seen[v[0]] = true
	expect_equal(last, FIST_VARIANT, "the fist is variant 32, not the PlayStation's %d" % hands.variant[0])
	expect(seen.size() >= 10, "a blend of many steps, not the PlayStation's four")
	hands.command(3, 4, 0)       # a shape: the value jumps to 0x203
	hands.update()
	expect_equal(ArcadePoses.hand_variants(hands), PackedInt32Array([35, 35]), "shape 4 is variant 35")
	hands.command(3, 0, 0)       # open again: set at once from a shape
	hands.update()
	expect_equal(ArcadePoses.hand_variants(hands), PackedInt32Array([0, 0]), "the open hand")


func test_wing_and_tail_values() -> void:
	var hands := FighterHands.new()
	hands.wing_variant = 17
	hands.current[0] = 0x100
	expect_equal(ArcadePoses.wing_variants(hands), PackedInt32Array([17, 16]), "the wing sequence's variant and the tail's level >> 4")


func _surface(triangles: int) -> CharacterModel.Surface:
	var surface := CharacterModel.Surface.new()
	surface.vertices.resize(3 * triangles * STRIDE)
	return surface


## A hand group of `distinct` variants (variant k holds k + 1 triangles) and `select` mapping the
## 41 variants onto them.
func _group(distinct: int, select: PackedInt32Array) -> CharacterModel.VariantGroup:
	var group := CharacterModel.VariantGroup.new()
	for k in distinct:
		group.variants.append([_surface(k + 1)])
	group.select = select
	return group


func _model(arcade: bool) -> CharacterModel:
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.directory = TEXTURE_DIR
	model.texture = TEXTURE
	model.arcade = arcade
	model.surfaces.append(_surface(1))
	var select := PackedInt32Array()
	for v in VARIANTS:
		select.append(0 if v < 8 else v - 7)       # variants 0–7 are one
	model.hands.append(_group(VARIANTS - 7, select))
	var right := _group(VARIANTS - 7, select)
	right.channel = 1
	model.hands.append(right)
	return model


func _hand_mesh(view: FighterView, variant: int, hand: int = 0) -> ArrayMesh:
	return (view.hand_meshes[hand] as Array)[variant] as ArrayMesh


func test_the_view_shows_an_arcade_hand_by_the_channels_value() -> void:
	if not require(TEXTURE_DIR.path_join(TEXTURE)):
		return
	var view := FighterView.new()
	view.setup(_model(true))
	expect_equal((view.hand_meshes[0] as Array).size(), VARIANTS, "a mesh for each of the 41 variants")
	expect(_hand_mesh(view, 0) == _hand_mesh(view, 7) and _hand_mesh(view, 8) != _hand_mesh(view, 7), "equal variants share their mesh")
	var hands := FighterHands.new()
	hands.current[0] = 0x200
	hands.current[1] = 0x203
	view.set_hands(hands)
	expect(view.hand_instances[0].mesh == _hand_mesh(view, FIST_VARIANT), "the fist: variant 32")
	expect(view.hand_instances[1].mesh == _hand_mesh(view, 35, 1), "channel 1 at 0x203: shape variant 35")
	hands.current[0] = 0x9F
	view.set_hands(hands)
	expect(view.hand_instances[0].mesh == _hand_mesh(view, 9), "0x9F >> 4")
	expect(view.hand_instances[0].mesh != _hand_mesh(view, 10), "and not its neighbour")
	hands.current[0] = 0x208
	view.set_hands(hands)
	expect(view.hand_instances[0].mesh == _hand_mesh(view, 40), "the last shape")
	view.free()
	var ps1 := FighterView.new()
	ps1.setup(_model(false))
	hands.variant[0] = 3
	ps1.set_hands(hands)
	expect(ps1.hand_instances[0].mesh == _hand_mesh(ps1, 3), "a PlayStation model takes the PlayStation's variant")
	ps1.free()


## A packed group of model.json: the first variant's surfaces, the moving vertices' positions per
## distinct variant, and per corner the vertices its positions are.
func test_a_packed_group_patches_the_corners_with_the_poses() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var corners := PackedFloat32Array()
	corners.resize(3 * STRIDE)
	for i in 3:
		corners[i * STRIDE] = 100.0 + i       # pa.x: later patched for corners 0 and 2
		corners[i * STRIDE + 3] = 200.0       # pb.x: stays for every corner
		corners[i * STRIDE + 23] = 300.0 + i  # pc.x
	# Two distinct variants of two moving vertices (x, y, z each).
	var table := PackedFloat32Array([1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16])
	var refs := PackedInt32Array([0, -1, 1, -1, 1, -1, -1, -1, 0])
	var blob := corners.to_byte_array()
	var table_at := blob.size()
	blob.append_array(table.to_byte_array())
	var refs_at := blob.size()
	blob.append_array(refs.to_byte_array())
	var file := FileAccess.open(DIR.path_join("mesh.bin.gz"), FileAccess.WRITE)
	file.store_buffer(blob.compress(FileAccess.COMPRESSION_GZIP))
	file.close()
	var select: Array = []
	for v in VARIANTS:
		select.append(v % 2)
	var data := {
		"source": "arcade", "vertex_floats": STRIDE, "surfaces": [], "parts": [], "wings": [],
		"hands": [{"channel": 1, "part": 17, "variants": [[{"double_sided": false, "offset": 0, "vertex_count": 3}]],
			"select": select, "poses": {"count": 2, "vertices": 2, "table": table_at, "refs": refs_at}}],
	}
	file = FileAccess.open(DIR.path_join("model.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var model := CharacterModel.load_from(DIR)
	expect(model.arcade, "the source is the arcade's")
	var group := model.hands[0]
	expect_equal([group.channel, group.part, group.variants.size(), group.select.size()], [1, 17, 2, VARIANTS], "the group")
	for pose in 2:
		var v := (group.variants[pose][0] as CharacterModel.Surface).vertices
		var base := 6 * pose
		expect_equal([v[0], v[1], v[2]], [table[base], table[base + 1], table[base + 2]], "corner 0's pa is vertex 0, pose %d" % pose)
		expect_equal([v[3], v[4], v[5]], [200.0, 0.0, 0.0], "corner 0's pb stays")
		expect_equal([v[23], v[24], v[25]], [table[base + 3], table[base + 4], table[base + 5]], "corner 0's pc is vertex 1")
		expect_equal([v[STRIDE], v[STRIDE + 1], v[STRIDE + 2]], [101.0, 0.0, 0.0], "corner 1's pa stays (the file's)")
		expect_equal([v[STRIDE + 3], v[STRIDE + 4], v[STRIDE + 5]], [table[base + 3], table[base + 4], table[base + 5]], "corner 1's pb is vertex 1")
		expect_equal(v[2 * STRIDE], 102.0, "corner 2's pa stays")
		expect_equal([v[2 * STRIDE + 23], v[2 * STRIDE + 24], v[2 * STRIDE + 25]], [table[base], table[base + 1], table[base + 2]], "corner 2's pc is vertex 0")
		expect_equal(v[2 * STRIDE + 3], 200.0, "other floats are the file's")
	DirAccess.remove_absolute(DIR.path_join("mesh.bin.gz"))
	DirAccess.remove_absolute(DIR.path_join("model.json"))
	DirAccess.remove_absolute(DIR)


## The converted arcade models: a hand group per hand with the 41 variants, whose fist differs from
## the old coarse variant 3, and the jaw of Kuma and Panda in place of the left hand.
func test_converted_hands_and_jaws() -> void:
	var dir := AssetCatalog.ROOT.path_join("characters/costume_00")
	if not require(dir.path_join("model.json")):
		return
	var model := CharacterModel.load_from(dir)
	if not model.arcade:
		skip("costume 0 is the PlayStation's model")
		return
	expect_equal(model.hands.size(), 2, "two hands")
	for hand in model.hands:
		expect_equal(hand.select.size(), VARIANTS, "the arcade's 41 variants")
		expect(hand.variants.size() > FIST_VARIANT and hand.variants.size() <= VARIANTS, "33 or more distinct")
		var open := _vertices(hand, 0)
		expect(open != _vertices(hand, 3), "variant 3 is barely closed, but not the open hand")
		expect(_vertices(hand, FIST_VARIANT) != _vertices(hand, 3), "the fist is not variant 3")
		expect(_vertices(hand, FIST_VARIANT) != open, "the fist is not the open hand")
		expect_equal(_vertices(hand, FIST_VARIANT).size(), open.size(), "the same faces in every variant")
	for slot: int in JAW_SLOTS:
		var jaw := CharacterModel.load_from(AssetCatalog.ROOT.path_join("characters/costume_%02d" % slot))
		expect_equal(jaw.hands.size(), 1, "slot %d: the jaw only" % slot)
		expect_equal([jaw.hands[0].channel, jaw.hands[0].part], [0, 17], "slot %d: driven by channel 0" % slot)
		expect(_vertices(jaw.hands[0], 0) != _vertices(jaw.hands[0], FIST_VARIANT), "slot %d: the mouth opens" % slot)


## The PlayStation's jaw (Kuma, Panda, Gon: channel 0 drives the head's rows) is a packed group of
## the ten variants a channel value selects; the view picks its mesh by FighterHands.variant.
func test_the_view_shows_a_playstation_jaw_by_the_hands_variant() -> void:
	if not require(TEXTURE_DIR.path_join(TEXTURE)):
		return
	var model := _model(false)
	model.hands.clear()
	var select := PackedInt32Array([0, 1, 2, 3, 4, 5, 0, 0, 0, 0])      # six distinct blocks, as Gon's
	var jaw := _group(6, select)
	jaw.part = 17
	model.hands.append(jaw)
	var view := FighterView.new()
	view.setup(model)
	expect_equal((view.hand_meshes[0] as Array).size(), PS1_VARIANTS, "a mesh for each of the ten variants")
	expect(_hand_mesh(view, 6) == _hand_mesh(view, 0) and _hand_mesh(view, 5) != _hand_mesh(view, 0), "equal variants share their mesh")
	var hands := FighterHands.new()
	hands.command(1, 1, 10)      # the jaw's channel: the fist's value over 11 steps
	for step in 12:
		hands.update(Character.KUMA)
	expect_equal(hands.variant[0], 3, "the coarse closed variant")
	view.set_hands(hands)
	expect(view.hand_instances[0].mesh == _hand_mesh(view, 3), "the jaw shows variant 3 of channel 0")
	hands.command(1, 7, 0)       # shape 7: value 0x206, variant 9
	hands.update(Character.KUMA)
	view.set_hands(hands)
	expect_equal(hands.variant[0], 9, "shape 7")
	expect(view.hand_instances[0].mesh == _hand_mesh(view, 9), "the last variant")
	view.free()


## The converted PlayStation models of Gon: his jaw (channel 0; his hands have no variants).
func test_converted_playstation_jaw() -> void:
	for slot: int in PS1_JAW_SLOTS:
		var dir := AssetCatalog.ROOT.path_join("characters/costume_%02d" % slot)
		if not require(dir.path_join("model.json")):
			return
		var model := CharacterModel.load_from(dir)
		if model.arcade:
			skip("costume %d is the arcade's model" % slot)
			return
		expect_equal(model.hands.size(), 1, "slot %d: the jaw only" % slot)
		var jaw := model.hands[0]
		expect_equal([jaw.channel, jaw.part, jaw.select.size()], [0, 17, PS1_VARIANTS], "slot %d: the jaw" % slot)
		expect(jaw.variants.size() < PS1_VARIANTS, "slot %d: packed to the distinct variants" % slot)
		expect(_vertices(jaw, 0) != _vertices(jaw, 3), "slot %d: the mouth opens" % slot)
		expect_equal(_vertices(jaw, 3).size(), _vertices(jaw, 0).size(), "slot %d: the same faces in every variant" % slot)


## Gon's head palette (PartSelectVertexVariant): the swapped atlas for hand variants 4 and 5 of either
## channel, decided call by call (channel 0's, then channel 1's) against the variant last seen.
func test_gons_head_palette_follows_the_hand_variants() -> void:
	if not require(TEXTURE_DIR.path_join(SWAP_TEXTURE)):
		return
	var model := _model(false)
	model.swap_texture = SWAP_TEXTURE
	model.swap_variants = PackedInt32Array([4, 5])
	var view := FighterView.new()
	view.setup(model)
	expect(view.texture_swap != null and view.texture_swap != view.texture_open, "the model has the swapped atlas")
	var hands := FighterHands.new()
	var cases := [
		[[0, 0], false, "nothing seen: his own palette"],
		[[4, 0], false, "channel 1 is called last: the saved palette is copied back"],
		[[0, 4], true, "variant 4 of channel 1 swaps it"],
		[[0, 4], true, "the same variants again: no new copy"],
		[[2, 5], true, "variant 5, and 2 before it"],
		[[5, 5], true, "variant 5 is already the last seen"],
		[[5, 3], false, "an ordinary variant restores it"],
		[[1, 2], false, "no swapping variant"],
		[[5, 0], false, "channel 0's swap is undone by channel 1's call"],
	]
	for c: Array in cases:
		hands.variant = PackedInt32Array(c[0] as Array)
		view.set_hands(hands)
		var swapped: bool = c[1]
		var shown: Texture2D = view.texture_swap if swapped else view.texture_open
		expect(view._albedo == shown, "%s: %s" % [c[0], c[2]])
	view.free()


## Under the overhead KO camera PartSelectVertexVariant leaves Gon's palette alone; his moves with
## flag 0x40000 swap it once, and only the next fight's set-up restores it.
func test_gons_palette_under_the_overhead_camera() -> void:
	if not require(TEXTURE_DIR.path_join(SWAP_TEXTURE)):
		return
	var model := _model(false)
	model.swap_texture = SWAP_TEXTURE
	model.swap_variants = PackedInt32Array([4, 5])
	var view := FighterView.new()
	view.setup(model)
	var hands := FighterHands.new()
	view.set_overhead(true, false)
	hands.variant = PackedInt32Array([5, 5])
	view.set_hands(hands)
	expect(view._albedo == view.texture_open, "the hand variants do not swap it under this camera")
	view.set_overhead(true, true)
	expect(view._albedo == view.texture_swap, "the chain move swaps it")
	hands.variant = PackedInt32Array([0, 0])
	view.set_overhead(true, false)
	view.set_hands(hands)
	expect(view._albedo == view.texture_swap, "and nothing copies it back")
	view.set_overhead(false, false)
	view.set_hands(hands)
	expect(view._albedo == view.texture_open, "the other camera: the hand variants decide again")
	view.free()


## The converted Gon (costume slots 42 and 43, PlayStation only): his swapped palette's atlas.
func test_converted_gon_palette() -> void:
	for slot: int in PS1_JAW_SLOTS:
		var dir := AssetCatalog.ROOT.path_join("characters/costume_%02d" % slot)
		if not require(dir.path_join("model.json")):
			return
		var model := CharacterModel.load_from(dir)
		if model.swap_texture == "":
			skip("costume %d was converted before the palette swap" % slot)
			return
		expect_equal(model.swap_variants, PackedInt32Array([4, 5]), "slot %d: variants" % slot)
		expect(FileAccess.file_exists(dir.path_join(model.swap_texture)), "slot %d: the atlas is there" % slot)
	for slot: int in [0, 22, 44]:
		var dir := AssetCatalog.ROOT.path_join("characters/costume_%02d" % slot)
		if FileAccess.file_exists(dir.path_join("model.json")):
			expect_equal(CharacterModel.load_from(dir).swap_texture, "", "slot %d has no palette swap" % slot)


func _vertices(group: CharacterModel.VariantGroup, variant: int) -> PackedFloat32Array:
	var all := PackedFloat32Array()
	var entry := group.select[variant] if not group.select.is_empty() else variant
	for surface: CharacterModel.Surface in group.variants[entry]:
		all.append_array(surface.vertices)
	return all
