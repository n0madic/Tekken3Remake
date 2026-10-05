extends TestSuite
## The arcade True Ogre's wing and tail variants: the converter's "wings" lists load as variant
## groups (CharacterModel.VariantGroup), FighterView swaps their meshes by the pose values it is
## given (the wing sequence's variant and the level channel's value >> 4), and the values the
## simulation produces stay inside the variants the converter writes (arcade/README.md#true-ogres-wings).

const STRIDE := 28
const WING_VARIANTS := 40
const TAIL_VARIANTS := 17
const DIR := "user://test_wing_variants"
const TEXTURE_DIR := "res://imported"
const TEXTURE := "icon.png"


func _surface(triangles: int) -> CharacterModel.Surface:
	var surface := CharacterModel.Surface.new()
	surface.vertices.resize(3 * triangles * STRIDE)
	return surface


## A group with `count` variants, variant k holding k + 1 triangles (so every mesh differs).
func _group(channel: int, count: int) -> CharacterModel.VariantGroup:
	var group := CharacterModel.VariantGroup.new()
	group.channel = channel
	for k in count:
		group.variants.append([_surface(k + 1)])
	return group


func _variant_mesh(view: FighterView, group: int, variant: int) -> ArrayMesh:
	return (view.wing_meshes[group] as Array)[variant] as ArrayMesh


func _model() -> CharacterModel:
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.directory = TEXTURE_DIR
	model.texture = TEXTURE
	model.surfaces.append(_surface(1))
	model.wings.append(_group(0, WING_VARIANTS))
	model.wings.append(_group(1, TAIL_VARIANTS))
	return model


func test_view_swaps_the_wing_and_tail_meshes() -> void:
	if not require(TEXTURE_DIR.path_join(TEXTURE)):
		return
	var view := FighterView.new()
	view.setup(_model())
	expect_equal(view.wing_instances.size(), 2, "an instance per wing group")
	expect_equal(view.wing_channels, PackedInt32Array([0, 1]), "with the pose value it follows")
	expect(view.hand_instances.is_empty(), "and no hands")
	for instance in view.wing_instances:
		expect_equal(instance.layers, StageLighting.FIGHTER_LAYER, "on the fighters' layer")
	view.set_wing_variants(PackedInt32Array([5, 3]))
	expect(view.wing_instances[0].mesh == _variant_mesh(view, 0, 5), "the wings' variant 5")
	expect(view.wing_instances[1].mesh == _variant_mesh(view, 1, 3), "the tail's variant 3")
	view.set_wing_variants(PackedInt32Array([-1, 99]))
	expect(view.wing_instances[0].mesh == _variant_mesh(view, 0, 0), "a negative value shows the first variant")
	expect(view.wing_instances[1].mesh == _variant_mesh(view, 1, TAIL_VARIANTS - 1), "a value past the end the last")
	view.free()


func test_hands_give_the_wing_and_tail_values() -> void:
	if not require(TEXTURE_DIR.path_join(TEXTURE)):
		return
	var view := FighterView.new()
	view.setup(_model())
	var hands := FighterHands.new()
	hands.wing_variant = 23
	hands.current[0] = FighterHands.OGRE_LEVEL
	view.set_hands(hands)
	expect(view.wing_instances[0].mesh == _variant_mesh(view, 0, 23), "the wing sequence's variant")
	expect(view.wing_instances[1].mesh == _variant_mesh(view, 1, TAIL_VARIANTS - 1), "the level 0x100 is the tail's variant 16")
	hands.current[0] = 0x4F
	view.set_hands(hands)
	expect(view.wing_instances[1].mesh == _variant_mesh(view, 1, 4), "the level >> 4")
	view.free()


## model.json with a "wings" list loads as variant groups next to the hands.
func test_model_loads_wing_groups() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var corner := PackedFloat32Array()
	corner.resize(3 * STRIDE)
	var mesh := corner.to_byte_array().compress(FileAccess.COMPRESSION_GZIP)
	var file := FileAccess.open(DIR.path_join("mesh.bin.gz"), FileAccess.WRITE)
	file.store_buffer(mesh)
	file.close()
	var surface := {"double_sided": false, "offset": 0, "vertex_count": 3}
	var data := {
		"vertex_floats": STRIDE, "surfaces": [surface], "parts": [],
		"hands": [{"channel": 1, "part": 12, "variants": [[surface], [surface]]}],
		"wings": [{"channel": 0, "part": 1, "variants": [[surface], [surface], [surface]]},
			{"channel": 1, "part": 18, "variants": [[surface]]}],
	}
	file = FileAccess.open(DIR.path_join("model.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var model := CharacterModel.load_from(DIR)
	expect_equal(model.hands.size(), 1, "the hand")
	expect_equal(model.wings.size(), 2, "the wing and tail groups")
	expect_equal([model.wings[0].channel, model.wings[0].part, model.wings[0].variants.size()], [0, 1, 3], "the wings")
	expect_equal([model.wings[1].channel, model.wings[1].part, model.wings[1].variants.size()], [1, 18, 1], "the tail")
	expect_equal(model.variant_groups().size(), 3, "all of them")
	var first := (model.wings[0].variants[0] as Array)[0] as CharacterModel.Surface
	expect_equal(first.vertices.size(), 3 * STRIDE, "a surface's corners")
	DirAccess.remove_absolute(DIR.path_join("mesh.bin.gz"))
	DirAccess.remove_absolute(DIR.path_join("model.json"))
	DirAccess.remove_absolute(DIR)


## The values the simulation gives True Ogre's view stay in the converter's ranges: the wing
## sequence's variants 0–39 (all of them reached) and the level >> 4 in 0–16.
func test_simulation_values_stay_in_the_converted_variants() -> void:
	if not require(AssetCatalog.ROOT + "tables/fighter.json"):
		return
	var tables := FighterTables.load_from(AssetCatalog.ROOT + "tables/fighter.json")
	var hands := FighterHands.new()
	hands.command(3, 2, 10, Character.TRUE_OGRE)
	var wings := {}
	var top_level := 0
	for step in 400:
		hands.update(Character.TRUE_OGRE, 1 if step < 300 else 0, tables)
		wings[hands.wing_variant] = true
		top_level = maxi(top_level, hands.current[0] >> ArcadePoses.TAIL_LEVEL_SHIFT)
		expect(hands.wing_variant >= 0 and hands.wing_variant < WING_VARIANTS, "wing variant %d at step %d" % [hands.wing_variant, step])
	expect_equal(wings.size(), WING_VARIANTS, "every wing variant is shown while he flies")
	expect_equal(top_level, TAIL_VARIANTS - 1, "the level reaches the tail's last variant")


## The converted arcade True Ogre: a wings group of 40 variants and a tail group of 17 that move.
func test_converted_true_ogre() -> void:
	var dir := AssetCatalog.ROOT.path_join("characters/costume_32")
	if not require(dir.path_join("model.json")):
		return
	var model := CharacterModel.load_from(dir)
	if model.wings.is_empty():
		skip("costume 32 is the PlayStation's model")
		return
	expect_equal(model.wings.size(), 2, "wings and tail")
	expect_equal(model.wings[0].variants.size(), WING_VARIANTS, "the wing sequence's variants")
	expect_equal(model.wings[1].variants.size(), TAIL_VARIANTS, "the level's variants")
	expect(_vertices(model.wings[0], 0) != _vertices(model.wings[0], 16), "the wings move between variants")
	expect(_vertices(model.wings[1], 0) != _vertices(model.wings[1], 16), "the tail moves with the level")
	expect_equal(_vertices(model.wings[0], 0).size(), _vertices(model.wings[0], 39).size(), "the same faces in every variant")


func _vertices(group: CharacterModel.VariantGroup, variant: int) -> PackedFloat32Array:
	var all := PackedFloat32Array()
	for surface: CharacterModel.Surface in group.variants[variant]:
		all.append_array(surface.vertices)
	return all
