extends TestSuite
## Whole matches against the game's own fight code (`work/traces/fight_<scenario>.bin`,
## tools/research/fight_harness.py): the same pads frame by frame, then every fighter field, the round
## state, the camera and the sound, vibration and music calls compared with the game's records;
## in the `cpu_` matches also the AI records of the CPU fighters.
## The `fixes_` matches run the game with the Gameplay fixes patched in (fight_harness.py) and
## the simulation with RuleSet.with_gameplay_fixes().

const SLOW := true                  ## the runner's --quick leaves the trace comparisons out
const MAX_REPORTED := 40
## Round-flow and camera globals compared each frame (address, size; negative: signed).
const GLOBALS := {
	"round state": [0x80097350, -2],
	"round counter": [0x80097354, -4],
	"round frame": [0x80095884, -4],
	"timer": [0x800AE094, -4],
	"camera phase": [0x80095890, -4],
	"camera pitch": [0x800A8A88, -4],
	"camera yaw": [0x800A8A8C, -4],
	"camera x": [0x800A8A9C, -4],
	"camera y": [0x800A8AA0, -4],
	"camera z": [0x800A8AA4, -4],
	"rand": [0x800A3E80, 4],
	"AI generator": [0x800AE168, 4],
	"display buffer": [0x800AE3C4, 4],
	"bar 0 health": [0x800980F4, -4],
	"bar 0 target": [0x800980F8, -2],
	"bar 0 drawn": [0x800980FA, -2],
	"bar 0 recent": [0x800980FC, -2],
	"bar 1 health": [0x80098104, -4],
	"bar 1 target": [0x80098108, -2],
	"bar 1 drawn": [0x8009810A, -2],
	"bar 1 recent": [0x8009810C, -2],
	"backdrop angle": [0x800A9650, 4],
	"backdrop prev yaw": [0x800A9658, 4],
	"backdrop yaw": [0x800A9664, 4],
	"look point x": [0x800AE0D8, -4],
	"look point z": [0x800AE0E0, -4],
}

var _content: FightContent


func test_paul_law() -> void:
	_run("paul_law")


func test_lei_king() -> void:
	_run("lei_king")


func test_yoshimitsu_nina() -> void:
	_run("yoshimitsu_nina")


func test_hwoarang_xiaoyu() -> void:
	_run("hwoarang_xiaoyu")


func test_eddy_jin() -> void:
	_run("eddy_jin")


func test_julia_kuma() -> void:
	_run("julia_kuma")


func test_bryan_heihachi() -> void:
	_run("bryan_heihachi")


func test_ogre_mokujin() -> void:
	_run("ogre_mokujin")


func test_jack_gon() -> void:
	_run("jack_gon")


func test_anna_doctorb() -> void:
	_run("anna_doctorb")


func test_trueogre_tiger() -> void:
	_run("trueogre_tiger")


func test_panda_anna() -> void:
	_run("panda_anna")


func test_xiaoyu_king_chip() -> void:
	_run("xiaoyu_king_chip")


func test_draw() -> void:
	_run("draw")


func test_perfect() -> void:
	_run("perfect")


func test_long_match() -> void:
	_run("long_match")


func test_fixes_paul_law() -> void:
	_run("fixes_paul_law")


func test_fixes_lei_king() -> void:
	_run("fixes_lei_king")


func test_fixes_yoshimitsu_nina() -> void:
	_run("fixes_yoshimitsu_nina")


func test_fixes_hwoarang_xiaoyu() -> void:
	_run("fixes_hwoarang_xiaoyu")


func test_fixes_eddy_jin() -> void:
	_run("fixes_eddy_jin")


func test_fixes_julia_kuma() -> void:
	_run("fixes_julia_kuma")


func test_fixes_bryan_heihachi() -> void:
	_run("fixes_bryan_heihachi")


func test_fixes_ogre_mokujin() -> void:
	_run("fixes_ogre_mokujin")


func test_fixes_jack_gon() -> void:
	_run("fixes_jack_gon")


func test_fixes_anna_doctorb() -> void:
	_run("fixes_anna_doctorb")


func test_fixes_trueogre_tiger() -> void:
	_run("fixes_trueogre_tiger")


func test_fixes_panda_anna() -> void:
	_run("fixes_panda_anna")


func test_fixes_xiaoyu_king_chip() -> void:
	_run("fixes_xiaoyu_king_chip")


func test_fixes_draw() -> void:
	_run("fixes_draw")


func test_fixes_perfect() -> void:
	_run("fixes_perfect")


func test_fixes_long_match() -> void:
	_run("fixes_long_match")


func test_cpu_paul_king() -> void:
	_run("cpu_paul_king")


func test_cpu_yoshimitsu_hwoarang() -> void:
	_run("cpu_yoshimitsu_hwoarang")


func test_cpu_ogre_jin() -> void:
	_run("cpu_ogre_jin")


func test_cpu_gon_nina() -> void:
	_run("cpu_gon_nina")


func test_cpu_king_law() -> void:
	_run("cpu_king_law")


func test_cpu_trueogre_xiaoyu() -> void:
	_run("cpu_trueogre_xiaoyu")


func test_cpu_spam_eddy() -> void:
	_run("cpu_spam_eddy")


func test_cpu_attract() -> void:
	_run("cpu_attract")


func test_cpu_vs_cpu() -> void:
	_run("cpu_vs_cpu")


func test_cpu_julia_heihachi() -> void:
	_run("cpu_julia_heihachi")


func _run(scenario: String) -> void:
	if not require(FightTrace.path(scenario), "run tools/research/export_traces.py --fight first"):
		return
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var trace := FightTrace.load_scenario(scenario)
	if trace == null:
		expect(false, "%s does not load" % scenario)
		return
	if _content == null:
		_content = FightContent.load_from(AssetCatalog.ROOT)
	var fixes: bool = (trace.header["scenario"] as Dictionary).get("gameplay_fixes", false)
	var rules := RuleSet.with_gameplay_fixes() if fixes else RuleSet.original()
	var sim := FightSimulation.new(_content, _setup(trace), rules)
	_compare(scenario, trace, sim)


func _compare(scenario: String, trace: FightTrace, sim: FightSimulation) -> void:
	var compare := FighterCompare.new(trace)
	var ai_compare := AiCompare.new(trace) if AiCompare.applies(trace) else null
	for frame in trace.frames:
		expect_equal(sim.main_state, trace.sub_state(frame), "%s frame %d FightMain state" % [scenario, frame])
		sim.step(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		var banks: Array[MotionBank] = [sim.fight.fighters[0].bank, sim.fight.fighters[1].bank, _content.common]
		var lines := PackedStringArray()
		for i in 2:
			for d in compare.differences(sim.fight.fighters[i], frame, i, banks):
				lines.append("fighter %d %s" % [i, d])
		if ai_compare != null:
			for slot in 2:
				lines.append_array(ai_compare.differences(sim.ai, slot, frame, banks))
		for name: String in GLOBALS:
			var g := JsonFile.ints(GLOBALS[name])
			if not trace.has_ram(g[0], absi(g[1])):
				continue                # recorded before the harness kept it
			var expected := trace.ram(frame, g[0], g[1])
			var actual := _global(sim, name)
			if RecordTrace.width(actual, g[1]) != expected:
				lines.append("%s: %d ≠ %d" % [name, actual, expected])
		var ours := FightCalls.of_events(sim.events)
		var theirs := FightCalls.of_trace(trace, frame)
		if ours != theirs:
			lines.append("calls: %s ≠ %s" % [ours, theirs])
		if not lines.is_empty():
			var shown := lines.slice(0, MAX_REPORTED)
			expect(false, "%s frame %d (FightMain %d, round state %d):\n    %s" % [scenario, frame,
				trace.sub_state(frame), sim.fight.round_state, "\n    ".join(shown)])
			return


func _global(sim: FightSimulation, name: String) -> int:
	var fight := sim.fight
	match name:
		"round state":
			return fight.round_state
		"round counter":
			return fight.round_counter
		"round frame":
			return fight.round_frame
		"timer":
			return fight.timer
		"camera phase":
			return fight.camera_phase
		"camera pitch":
			return sim.camera.view.pitch
		"camera yaw":
			return sim.camera.view.yaw
		"camera x":
			return sim.camera.view.x
		"camera y":
			return sim.camera.view.y
		"camera z":
			return sim.camera.view.z
		"rand":
			return fight.rng.state
		"AI generator":
			return fight.ai_rng
		"display buffer":
			return fight.display_buffer
		"backdrop angle":
			return fight.backdrop.angle
		"backdrop prev yaw":
			return fight.backdrop.prev_yaw
		"backdrop yaw":
			return fight.backdrop.yaw
		"look point x":
			return fight.backdrop.point_x
		"look point z":
			return fight.backdrop.point_z
	if name.begins_with("bar "):
		var bar := fight.hud_bars[name.substr(4, 1).to_int()]
		return bar[["health", "target", "drawn", "recent"].find(name.get_slice(" ", 2))]
	return 0


static func _setup(trace: FightTrace) -> FightSetup:
	var s: Dictionary = trace.header["scenario"]
	var setup := FightSetup.new()
	setup.chars = JsonFile.ints(s["chars"])
	setup.costumes = JsonFile.ints(s["costumes"])
	setup.stage = JsonFile.number(s["stage"])
	setup.seed = JsonFile.number(s["seed"])
	setup.round_time = JsonFile.number(s["round_time"])
	setup.rounds = JsonFile.number(s["rounds"])
	setup.chip_damage = s["chip"]
	var cpu: Variant = s.get("cpu")
	if cpu is Array:
		setup.cpu = JsonFile.ints(cpu)
		setup.ai_difficulty = JsonFile.number(s["difficulty"])
		setup.ai_level = JsonFile.number(s["level"])
		setup.attract = s["attract"]
	var tables: Variant = s.get("key_tables")
	if tables is Array:
		var list: Array = tables
		for p in 2:
			setup.key_tables[p] = JsonFile.ints(list[p])
	return setup
