extends TestSuite
## Mokujin's stick (attachment part 18, held by joint 10): FUN_800363B0 draws it only while he has
## Yoshimitsu's moves (bank type 4), and it is drawn from the joints as composed, not from the
## sword points CollisionShapesUpdate writes into joint blocks 18 and 19 for that bank.
## The seeds pick the banks the harness picks (tools/research/fight_harness.py, P1 Mokujin vs Paul).

const SEED_YOSHIMITSU := 1234          ## the round's bank is 4
const SEED_OTHER := 1                  ## the round's bank is 1
const FRAMES := 60
const HAND := 10
const STICK := 18
var stick_offset := PackedInt32Array([104, 3, -9])      ## costume slot 30's KMD offset (z negated)
var sword_point := PackedInt32Array([100, -720, 0])


func _fight(seed: int) -> FighterState:
	var setup := FightSetup.new()
	setup.chars = PackedInt32Array([Character.MOKUJIN, 0])
	setup.seed = seed
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), setup, RuleSet.original())
	for i in FRAMES:
		sim.step(PackedInt32Array([0, 0]))
	return sim.fight.fighters[0]


static func _point(joint: JointFrame, p: PackedInt32Array) -> PackedInt32Array:
	var m := joint.rot
	var out := PackedInt32Array([0, 0, 0])
	for r in 3:
		out[r] = joint.t[r] + ((m[3 * r] * p[0] + m[3 * r + 1] * p[1] + m[3 * r + 2] * p[2]) >> 12)
	return out


func test_stick_with_yoshimitsu_moves() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var f := _fight(SEED_YOSHIMITSU)
	expect_equal(f.bank_type, 4, "Yoshimitsu's bank")
	expect(f.body.stick_shown, "the stick is drawn")
	var hand := f.body.draw_joints[HAND]
	expect_equal(f.body.draw_joints[STICK].t, _point(hand, stick_offset), "the stick is drawn in the hand")
	expect_equal(f.body.joints[STICK].t, _point(f.body.joints[HAND], sword_point), "the sword point for collisions")


func test_no_stick_with_other_moves() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var f := _fight(SEED_OTHER)
	expect(f.bank_type != 4, "another character's bank")
	expect(not f.body.stick_shown, "the stick is not drawn")
