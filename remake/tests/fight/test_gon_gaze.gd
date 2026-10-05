extends TestSuite
## Gon's eyes' look direction in the fight (FighterAnimation._gon_eyes_follow, GonEyesFollow): fed
## from the joints of the two heads, only while the fighter looks at the opponent (no_look_at is 0)
## and the fight runs, and kept when the body is rebuilt. The value itself is checked against the
## game in tests/core/test_gon_eyes.gd.

const FRAMES := 90
const HEAD := 2
const MARKER := 99                      ## a gaze no fight produces (the shifts are −17 to 17)


func _fight(cpu_gon: int) -> FightSimulation:
	var setup := FightSetup.new()
	setup.chars = PackedInt32Array([Character.GON, Character.PAUL])
	setup.cpu = PackedInt32Array([cpu_gon, 0])
	setup.seed = 3
	return FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), setup, RuleSet.original())


func test_the_gaze_follows_the_opponent_and_stays_in_range() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _fight(0)
	var seen := {}
	for i in FRAMES:
		sim.step(PackedInt32Array([0, 0]))
		var gaze := sim.fight.fighters[0].body.gon_gaze
		seen[gaze] = true
		expect(gaze >= -FighterAnimation.GAZE_RANGE and gaze <= FighterAnimation.GAZE_RANGE, "frame %d: %d in range" % [i, gaze])
	expect(seen.size() > 1 or not seen.has(0), "the gaze is not the unset 0 all the time (%s)" % [seen.keys()])
	var f := sim.fight.fighters[0]
	var opp := sim.fight.fighters[1]
	sim.animation._gon_eyes_follow(f, opp)
	var head := f.body.joints[HEAD]
	expect_equal(f.body.gon_gaze, FighterAnimation.gon_gaze(head.rot, head.t, opp.body.joints[HEAD].t, sim.fight.tables.camera),
		"the joints of both heads are what it is made of")
	opp.body.joints[HEAD].t = PackedInt32Array([head.t[0] + 4000, head.t[1], head.t[2]])
	sim.animation._gon_eyes_follow(f, opp)
	var right := f.body.gon_gaze
	opp.body.joints[HEAD].t = PackedInt32Array([head.t[0] - 4000, head.t[1], head.t[2]])
	sim.animation._gon_eyes_follow(f, opp)
	expect(right != f.body.gon_gaze, "an opponent on the other side gives another shift (%d, %d)" % [right, f.body.gon_gaze])


## One animation pass over the fighters with Gon's gaze set to a marker: it is replaced when he looks
## at the opponent and the fight runs, and kept when he does not (HeadLookAt keeps the head the
## same way) or when the fight is frozen (hit freeze, pause).
func _after_pass(no_look_at: int, freeze: int) -> int:
	var sim := _fight(0)
	for i in FRAMES:
		sim.step(PackedInt32Array([0, 0]))
	var f := sim.fight.fighters[0]
	var opp := sim.fight.fighters[1]
	var head := f.body.joints[HEAD]
	opp.body.joints[HEAD].t = PackedInt32Array([head.t[0] + 4000, head.t[1], head.t[2]])
	f.body.gon_gaze = MARKER
	f.no_look_at = no_look_at
	sim.fight.freeze = freeze
	sim.animation.update_all(sim.fighter_view, true, false)
	return f.body.gon_gaze


func test_no_look_at_or_a_freeze_keeps_the_gaze() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	expect(_after_pass(0, 0) != MARKER, "looking at the opponent in a running fight: the gaze is new")
	expect_equal(_after_pass(1, 0), MARKER, "not looking at the opponent: unchanged")
	expect_equal(_after_pass(0, 5), MARKER, "frozen: unchanged")


## Rebuilding a fighter's body for a new round keeps the look (FighterBody.keep_matrices).
func test_a_rebuilt_body_keeps_the_gaze() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _fight(0)
	sim.step(PackedInt32Array([0, 0]))
	var old := sim.fight.fighters[0].body
	old.gon_gaze = 7
	var rebuilt := FighterBody.new(old.model, sim.fight.tables.fighter, sim.fight.tables.pose, sim.animation.solver)
	rebuilt.keep_matrices(old)
	expect_equal(rebuilt.gon_gaze, 7, "kept")
