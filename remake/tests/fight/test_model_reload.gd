extends TestSuite
## A model swapped in during a fight (Tekken Force's enemies and boss, the Ogre scene) counts for
## its record only: the presentation replaces that fighter and keeps the rest of the fight view.


func test_reload_counts_for_its_record() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var setup := FightSetup.new()
	setup.chars = PackedInt32Array([Character.PAUL, Character.LAW])
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), setup, RuleSet.original())
	var loads := sim.loads
	expect(loads > 0, "the fight's set-up counts as a load")
	expect_equal(sim.model_loads, PackedInt32Array([0, 0, 0]), "no model swapped yet")
	sim.reload_fighter(1)
	expect_equal(sim.loads, loads, "a swapped model is no new fight")
	expect_equal(sim.model_loads, PackedInt32Array([0, 1, 0]), "it counts for its record")
