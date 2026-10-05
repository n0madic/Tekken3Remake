extends TestSuite
## A branch row whose slot is empty in both fighters' banks leads nowhere (game-bugs.md #61: the
## original reads a garbage row). Ogre's move 1990 has such a row (button 4 → slot 0x7DD, empty in
## the banks of Ogre and Yoshimitsu, and 0xDC5 is empty in both too): the CPU's follow-up lists
## and candidates used to dereference the missing move.

const FRAMES := 4000
## (AI group, CPU level, seed) of the runs that crashed.
const RUNS := [[2, 9, 1194], [3, 0, 1971]]


func _run(group: int, level: int, seed: int) -> FightSimulation:
	var setup := FightSetup.new()
	setup.chars = PackedInt32Array([Character.OGRE, Character.YOSHIMITSU])
	setup.cpu = PackedInt32Array([1, 1])
	setup.ai_difficulty = group
	setup.ai_level = level
	setup.seed = seed
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), setup, RuleSet.original())
	for i in FRAMES:
		sim.step(PackedInt32Array([0, 0]))
	return sim


func test_empty_slot_is_missing_in_both_banks() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _run(2, 9, 1194)
	var table: Array = sim.fight.slots[0]
	expect(table[0x7DD] == null, "slot 0x7DD of Ogre vs Yoshimitsu has no move")


func test_cpu_runs_without_errors() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	for r: Array in RUNS:
		_run(r[0] as int, r[1] as int, r[2] as int)
