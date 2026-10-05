extends RefCounted
## The report of coverage_report.gd (the entry point loads this script once the autoloads exist).
## The table goes to standard output with `print`, as fight_debug.gd's output does: it is the tool's
## result to read or pipe, not a log message (no `[info]` prefix on its rows).

const SCENARIOS := ["paul_law", "lei_king", "yoshimitsu_nina", "hwoarang_xiaoyu", "eddy_jin",
	"julia_kuma", "bryan_heihachi", "ogre_mokujin", "jack_gon", "anna_doctorb", "trueogre_tiger",
	"panda_anna", "xiaoyu_king_chip", "draw", "perfect"]
const TALL := Vector2(900, 1950)
const JUMP := 0.1


class Stats:
	var frames := 0
	var shown_sum := 0.0
	var shown_min := 1.0
	var capped := 0          ## frames with no extension beyond the 4:3 frame
	var jumps := 0


func run() -> void:
	var content := FightContent.load_from(AssetCatalog.ROOT)
	print("stage  kind       frames  tall: mean  min   none   jumps")
	for scenario: String in SCENARIOS:
		var trace := FightTrace.load_scenario(scenario)
		var s: Dictionary = trace.header["scenario"]
		var setup := FightSetup.new()
		setup.chars = JsonFile.ints(s["chars"])
		setup.costumes = JsonFile.ints(s["costumes"])
		setup.stage = JsonFile.number(s["stage"])
		setup.seed = JsonFile.number(s["seed"])
		setup.round_time = JsonFile.number(s["round_time"])
		setup.rounds = JsonFile.number(s["rounds"])
		setup.chip_damage = s["chip"]
		var sim := FightSimulation.new(content, setup, RuleSet.original())
		var stage := StageData.load_from(AssetCatalog.ROOT + "stages/" + FightContent.STAGE_LETTERS[setup.stage])
		var rig := CameraRig.new()
		rig.coverage = stage.coverage if setup.stage != FightView.CLEAR_STAGE else PackedInt32Array()
		var stats := {}
		var last := {}
		for frame in trace.frames:
			sim.step(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
			if sim.fight.camera_phase < 2:
				continue
			var kind := _kind(sim)
			var v := sim.camera.view
			rig.set_view(CameraView.new(v.pitch, v.yaw, v.x, v.y, v.z, v.h), true)
			rig.place(1.0, TALL)
			# How much of the symmetric upward extension the backdrop allows (1: all of it).
			var shown := rig.frame_rect
			var extra := shown.position.y / ((1.0 - shown.size.y) / 2.0)
			if not stats.has(kind):
				stats[kind] = Stats.new()
			var st: Stats = stats[kind]
			st.frames += 1
			st.shown_sum += extra
			st.shown_min = minf(st.shown_min, extra)
			if extra <= 0.001:
				st.capped += 1
			var previous: float = last.get(kind, extra)
			if absf(extra - previous) > JUMP:
				st.jumps += 1
			last[kind] = extra
		for kind: String in stats:
			var st: Stats = stats[kind]
			print("%-6s %-10s %6d  %9.2f  %4.2f  %5d  %5d" % [FightContent.STAGE_LETTERS[setup.stage], kind, st.frames,
				st.shown_sum / st.frames, st.shown_min, st.capped, st.jumps])
		rig.free()


static func _kind(sim: FightSimulation) -> String:
	var c := sim.camera
	if sim.fight.replay_playing != 0:
		return "replay"
	if sim.fight.camera_phase >= 3:
		return "round end"
	match c.state:
		3, 6, 2, 4:
			return "throw"
		8:
			return "hit"
	return "fight"
