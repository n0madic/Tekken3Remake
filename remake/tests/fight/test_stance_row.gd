extends TestSuite
## Bug #61 (not reproduced): a move whose stance slot 0xDC5 is empty in both banks has no stance
## row; the readers of that row treat it as standing instead of reading garbage.

const EMPTY_STANCE_SLOT := 0x2BF     ## bank 0 (Paul): a move whose stance slot is 0xDC5


func test_missing_stance_row() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), FightSetup.new(), RuleSet.original())
	sim.step(PackedInt32Array([0, 0]))
	var f := sim.fight.fighters[0]
	expect_equal(f.bank_type, 0, "Paul's bank")
	var row := sim.fight.move_for_slot(f, EMPTY_STANCE_SLOT)
	expect(row != null and row.stance_slot == FightSimulation.FALLBACK_SLOT, "the move ends in slot 0xDC5")
	expect(sim.fight.move_for_slot(f, FightSimulation.FALLBACK_SLOT) == null, "slot 0xDC5 is empty in both banks")
	f.pose_move = row
	f.move_row = null
	f.script_input = 0x1234
	sim.round_flow._hold_input(f)
	expect_equal(f.script_input, 0, "no stance row: no hold")
