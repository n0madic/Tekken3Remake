extends TestSuite
## A model swapped in during a fight (FightView.replace_fighter): only that record's view is built
## again, in the old one's place among the view's children, hidden until the next step shows it;
## the other fighters and the stage stay.


func test_replace_fighter_keeps_the_rest() -> void:
	var effects_dir := AssetCatalog.ROOT.path_join("effects")
	if not require(effects_dir.path_join("effects.json")):
		return
	var content := FightContent.load_from(AssetCatalog.ROOT)
	var slots := PackedInt32Array([0, 4])
	var models: Array[CharacterModel] = [content.model(slots[0]), content.model(slots[1])]
	var view := FightView.new()
	# In the tree, as in a fight: the camera rig parents its camera there, and it goes with the view.
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.setup(content.stage_number(0), EffectData.load_from(effects_dir), models, slots, PackedInt32Array([0, 1]))
	var kept := view.fighters[0]
	var old := view.fighters[1]
	var stage := view.stage_view
	var place := old.get_index()
	view.replace_fighter(1, content.model(8), 8)
	expect(view.fighters[0] == kept, "the other fighter stays")
	expect(view.stage_view == stage, "the stage stays")
	expect(view.fighters[1] != old and view.fighters[1].model == content.model(8), "the record's new model")
	expect_equal(view.fighters[1].get_index(), place, "in the old view's place")
	expect(not view.fighters[1].visible, "hidden until the next step shows it")
	expect(old.get_parent() == null and old.is_queued_for_deletion(), "the old view is gone")
	expect_equal(view.fighters.size(), 2)
	view.free()
