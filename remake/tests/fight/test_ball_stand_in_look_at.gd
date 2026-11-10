extends TestSuite
## Tekken Ball's stand-in attacker (the third record, FighterState.copy_from of the hitter's whole
## record, skeleton included): a fighter the charged ball hits has it for its opponent and turns
## its head towards the joints it was copied with (issue n0madic/Tekken3Remake#36: there was no
## skeleton to look at).

const DISC_DATA := true
const FRAMES := 30
const THIRD := 2
const HEAD := 2


func _fight() -> FightSimulation:
	var setup := FightSetup.new()
	setup.chars = PackedInt32Array([Character.PAUL, Character.LAW])
	setup.seed = 3
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), setup, RuleSet.original())
	for i in FRAMES:
		sim.step(PackedInt32Array([0, 0]))
	return sim


## Fighter 0 in a move that looks at its opponent, in the fight's camera phase.
static func _looking(sim: FightSimulation) -> FighterState:
	var f := sim.fight.fighters[0]
	var pose := MoveRow.new()
	pose.flags = MoveFlag.LOOK_AT
	f.pose_move = pose
	sim.fight.camera_phase = CameraPhase.FIGHT
	return f


func test_the_copy_holds_the_hitters_joints_apart() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _fight()
	var hitter := sim.fight.fighters[1]
	var third := sim.fight.fighters[THIRD]
	third.copy_from(hitter)
	var head := hitter.body.joints[HEAD].t.duplicate()
	expect_equal(third.body.joints[HEAD].t, head, "the joints as they were")
	expect(third.body != hitter.body, "a skeleton of its own")
	hitter.body.joints[HEAD].t[0] += 100
	expect_equal(third.body.joints[HEAD].t, head, "the hitter's next pose leaves the copy as it is")


func test_a_fighter_hit_by_the_stand_in_looks_at_its_joints() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var at_opponent := _fight()
	var f := _looking(at_opponent)
	at_opponent.animation._head_look_at(f, at_opponent.fight.fighters[1])
	var by_ball := _fight()
	var g := _looking(by_ball)
	by_ball.fight.fighters[THIRD].copy_from(by_ball.fight.fighters[1])
	by_ball.fight.fighters[THIRD].index = THIRD
	g.was_hit_this_move = 1
	g.last_attacker = THIRD
	var stand_in := by_ball.fight.opponent(g)
	expect_equal(stand_in.index, THIRD, "the opponent is the stand-in")
	by_ball.animation._head_look_at(g, stand_in)
	expect_equal(g.body.look_at.active, 1, "looking")
	expect_equal(g.body.look_at.target, f.body.look_at.target, "towards the joints the copy holds")
