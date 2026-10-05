extends TestSuite
## The Gameplay fixes that the fight traces rarely reach (game-bugs.md #8, #9, #41): the fixed
## arithmetic agrees with plain geometry where the game's 32-bit products wrap, and Tekken Force's
## enemy slots keep their timers past nine minutes in one level.

const TABLES := AssetCatalog.ROOT + "tables/pose.json"
const CASES := 2000
const LONG_LEVEL := 40000              ## level clock frames: past the 16-bit timers' 32,767


## #41: a defeated enemy (slot state 6) waits 60 frames before it blinks out (state 7). After
## 32,708 frames in a level the game's 16-bit timer reads as already expired; the fix waits.
func test_force_slot_timers_fix() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var content := FightContent.load_from(AssetCatalog.ROOT)
	for fixed: bool in [false, true]:
		var rules := RuleSet.original()
		rules.fix_force_slot_timers = fixed
		var fight := FightState.new(null, rules)
		var force := TekkenForce.new(fight, content.mode_ram("force"))
		fight.force = force
		force.assign_records()
		force.put32(TekkenForce.slot(0), FighterState.address(1))
		force.put32(TekkenForce.CLOCK, LONG_LEVEL)
		force.put16(TekkenForce.slot(0) + 8, 6)
		force._set_timer(0, TekkenForce.SLOT_TIMER, LONG_LEVEL + 0x3C)
		force._enemy_slot(null, 0, fight.fighters[0], SimEvents.new())
		expect_equal(force.slot_state(0), 6 if fixed else 7, "fixed %s: the defeated enemy's wait" % fixed)


## #9: SegmentHitsCylinder on level segments of 1,000–5,000 units whose closest point lies
## inside them, a few thousand units from the axis: the foot of the perpendicular needs
## products beyond 32 bits. The exact version agrees with the real distance (up to the game's
## integer rounding); the game's does not.
func test_segment_fix_follows_the_geometry() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var exact_wrong := 0
	var game_wrong := 0
	for i in CASES:
		var cyl := PackedInt32Array([rng.randi_range(-2000, 2000), 0, rng.randi_range(-2000, 2000), 400, 160000])
		var angle := rng.randf() * TAU
		var offset := rng.randf_range(-1500, 1500)
		var half := rng.randf_range(500, 2500)
		var dir := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-dir.y, dir.x)
		var centre := Vector2(cyl[0], cyl[2]) + normal * offset + dir * rng.randf_range(-half, half) * 0.5
		var a := centre - dir * half
		var b := centre + dir * half
		var seg := PackedInt32Array([int(a.x), 0, int(a.y), int(b.x), 0, int(b.y)])
		var distance := Geometry2D.get_closest_point_to_segment(Vector2(cyl[0], cyl[2]),
			Vector2(seg[0], seg[2]), Vector2(seg[3], seg[5])).distance_to(Vector2(cyl[0], cyl[2]))
		if absf(distance - cyl[3]) < 4.0:
			continue
		var truth := distance <= cyl[3]
		if FightMath.segment_hits_cylinder(seg, cyl, true) != truth:
			exact_wrong += 1
		if FightMath.segment_hits_cylinder(seg, cyl, false) != truth:
			game_wrong += 1
	expect_equal(exact_wrong, 0, "exact segment tests that miss the geometry")
	expect(game_wrong > 0, "the game's wrapped products change some results (bug #9)")


## #8: the arm bend for targets 72–74 units away (closer ones get no bend). Fixed, the elbow
## matrix changes smoothly into the one at 75; the game's wrapped product bends it elsewhere.
func test_elbow_fix_bends_smoothly() -> void:
	if not require(TABLES):
		return
	var tables := PoseTables.load_from(TABLES)
	var reference := _elbow(tables, 75, true)
	var fixed_jump := 0
	var game_jump := 0
	for length: int in [72, 73, 74]:
		fixed_jump = maxi(fixed_jump, _difference(_elbow(tables, length, true), reference))
		game_jump = maxi(game_jump, _difference(_elbow(tables, length, false), reference))
	expect(fixed_jump < 400, "fixed elbow near the 74-unit bend (largest change %d)" % fixed_jump)
	expect(game_jump > 1000, "the game's elbow jumps (bug #8, largest change %d)" % game_jump)


## The Gameplay fixes option can change in the middle of a session: the pose solver follows the
## rule set's flag (fix #8) on every solve, not only as it was when the fight was built.
func test_elbow_fix_follows_the_option() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var rules := RuleSet.original()
	var sim := FightSimulation.new(FightContent.load_from(AssetCatalog.ROOT), FightSetup.new(), rules)
	var pose := PackedInt32Array()
	pose.resize(128)
	var slots: Array[PackedInt32Array] = []
	for i in FighterBody.JOINTS:
		slots.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
	sim.animation._solve(pose, slots)
	expect(not sim.animation.solver.wide_elbow, "off with the original rules")
	rules.set_gameplay_fixes(true)
	sim.animation._solve(pose, slots)
	expect(sim.animation.solver.wide_elbow, "on once the option is switched on")
	rules.set_gameplay_fixes(false)
	sim.animation._solve(pose, slots)
	expect(not sim.animation.solver.wide_elbow, "and off again")


static func _elbow(tables: PoseTables, length: int, wide: bool) -> PackedInt32Array:
	var solver := PoseSolver.new(tables)
	solver.wide_elbow = wide
	var slots: Array[PackedInt32Array] = []
	for i in 2:
		slots.append(PackedInt32Array([0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000]))
	solver._solve_limb(PackedInt32Array([length, 0, 0]), 0, true, slots, 0, 1)
	return slots[1]


static func _difference(a: PackedInt32Array, b: PackedInt32Array) -> int:
	var worst := 0
	for i in 9:
		worst = maxi(worst, absi(a[i] - b[i]))
	return worst
