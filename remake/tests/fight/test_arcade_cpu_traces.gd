extends TestSuite
## The arcade's CPU against the program's own (`work/traces/arcade_cpu_*.bin`,
## tools/research/arcade_fight_harness.py): the same panel words frame by frame, then every fighter
## field, the AI record, the candidate table, the step the chain took, the AI's generator and `rand`
## compared with the game's. Needs a conversion from MAME's set alone (`manifest.source` "arcade");
## skipped otherwise.
##
## The camera has its own suite, and nothing here is taken from the traces past the first frame.

const SLOW := true
const MAX_REPORTED := 40
const CAMERA_RNG := 0x8021FB5C
const FRAME_RNG := 0x8021F838
const MAIN_FRAMES := 0x8021FDA4
const ROOT_CHANNELS := 0x8021FAC8
const ROUNDS := 0x80374F36
const ROUND_TIME := 0x8021FC84
const NEUTRAL_GUARD := 0x8021FC70
const CPU_GROUP := 0x8021FB74
const GAME_MODE := 0x80374F18
const LIFE_VERSUS := 0x8021FC54
const LIFE_ONE := 0x8021FDD0
const JOINED := 0x80374F33
const BOTH_JOINED := 3
const START_LOCKED := 0x8021FC5C
const CHARS := 0x8021FBF0
const COSTUMES := 0x8021FC0C
const DIFFICULTY := 0x8021FD28
const LEVEL := 0x8021FD40
const ATTRACT := 0x8021FC64
const LCG := 0x8021F8DC
const STEP := 0x8021F394
const CONTROL := 0x34A
const FIRST_CPU_CONTROL := 3            ## +0x34A: a human's is its player + 1, a CPU's its player + 3
const RECORDS := 0x8029CF00
const RECORD_BYTES := 0x364
const BRANCH_ROWS := 0x800ACA38
const BRANCH_ROW_BYTES := 12
const CANDIDATES := 0x8029D5C8
const CANDIDATE_BYTES := 12
const CANDIDATE_MARK := 0
const CANDIDATE_TARGET := 4
const CANDIDATE_ROW := 8
const PARAMS_AT := 0x2D4
const OWN_BANDS_AT := 0x34C
const OPP_BANDS_AT := 0x358
const HISTORY_AT := 0x268
const OPP_BREATH_AT := 0x274
const SCRIPT_AT := 0xC
const HOOK_OPPONENT_AT := 0xB8
const HOOK_OWN_AT := 0xBC
const FILTER_AT := 0xC0
const THROW_ROW_AT := 0x12C
const FRAME_COUNT_AT := 4
const PAD_AT := 6
const PREV_PAD_AT := 8
## What the game keeps at 0 or in a pointer of no meaning here, and the record does not hold:
## nothing but the reset writes these words. +0x10 is a table pointer the record has as `AiTables`.
const ALWAYS_ZERO: Array[int] = [0xA8, 0xAC, 0x218, 0x254, 0x264, 0x280]
const S32_FIELDS := {
	"slot": 0, "move_changed": 0x1C, "band": 0x20, "reach_band": 0x24, "wobble": 0x28, "wobble_phase": 0x2C,
	"prev_distance": 0x30, "distance_change": 0x34, "far_count": 0x38, "move_frames": 0x3C, "health_seen": 0x40,
	"pose_frame_seen": 0x44, "neutral_action": 0x48, "approach": 0x4C, "approach_kind": 0x50, "crouching": 0x54,
	"guarding": 0x58, "approach_hold": 0x5C, "setup_cooldown": 0x60, "neutral_cooldown": 0x64, "air_cooldown": 0x68,
	"direction_hold": 0x6C, "crouch_timer": 0x70, "crouch_attack_hold": 0x74, "move_frame_seen": 0x78,
	"attacking": 0x7C, "special_open": 0x80, "whiff_timer": 0x84, "wait": 0x98, "guard_holds": 0x9C,
	"guard_delay": 0xA0, "cancel_wait": 0xA4, "candidate_count": 0xB0, "marked_count": 0xB4,
	"announced_frames": 0xC4, "passed_frames": 0xC8, "vs_stance": 0xCC, "move_block": 0xD0, "guard_suspend": 0xD4,
	"parried": 0xE4, "punish": 0xE8, "throw_next": 0xEC, "throw_chance": 0xF0, "evade_reason": 0xF4,
	"guard_memory": 0xF8, "evasion": 0xFC, "throw_steps": 0x100, "throw_list": 0x104, "throw_press_frame": 0x128,
	"strings_on": 0x130, "no_strings": 0x148, "planned_on": 0x150, "link_skip": 0x220, "links_on": 0x224,
	"link_last": 0x258, "attacks_in_row": 0x25C, "attack_limit": 0x260, "history_same": 0x278,
	"opp_move_changed": 0x27C, "opp_down": 0x284, "opp_until": 0x288, "opp_coming": 0x28C, "opp_unblockable": 0x290,
	"opp_charging": 0x294, "coming_seen": 0x298, "opp_grabs": 0x29C, "opp_string": 0x2A0, "opp_joint_y": 0x2A4,
	"opp_high": 0x2AC, "neutral_block": 0x2B0, "neutral_frames": 0x2B4, "neutral_actions": 0x2B8, "own_word": 0x2BC,
	"own_state": 0x2C0, "own_attack": 0x2C4, "opp_word": 0x2C8, "opp_state": 0x2CC, "opp_attack": 0x2D0,
}
const MOVE_FIELDS := {
	"collected_move": 0x88, "pressed_move": 0x8C, "last_attack": 0x90, "continuation": 0x94, "throw_move": 0x10C,
}
## Branch row lists: the record's indices, the size's and the first entry's offset.
const LIST_FIELDS := {"strings": [0x134, 0x138], "planned": [0x154, 0x158], "links": [0x228, 0x22C]}

var _content: ArcadeFightContent


func test_cpu_vs_paul() -> void:
	_run("cpu_vs_paul")


func test_cpu_king() -> void:
	_run("cpu_king")


func test_cpu_vs_yoshimitsu() -> void:
	_run("cpu_vs_yoshimitsu")


func test_cpu_hwoarang() -> void:
	_run("cpu_hwoarang")


func test_cpu_vs_ogre() -> void:
	_run("cpu_vs_ogre")


func test_cpu_yoshimitsu() -> void:
	_run("cpu_yoshimitsu")


func test_cpu_ogre() -> void:
	_run("cpu_ogre")


func test_cpu_region_group() -> void:
	_run("cpu_region_group")


func test_cpu_past_ladder() -> void:
	_run("cpu_past_ladder")


func test_cpu_attract() -> void:
	_run("cpu_attract")


func test_cpu_vs_paul_smasher() -> void:
	_run("cpu_vs_paul_smasher")


func test_cpu_vs_true_ogre() -> void:
	_run("cpu_vs_true_ogre")


func test_cpu_king_ground() -> void:
	_run("cpu_king_ground")


func test_cpu_king_standing() -> void:
	_run("cpu_king_standing")


func test_cpu_king_crouching() -> void:
	_run("cpu_king_crouching")


func test_cpu_hwoarang_ducking() -> void:
	_run("cpu_hwoarang_ducking")


func test_cpu_hwoarang_setup() -> void:
	_run("cpu_hwoarang_setup")


func _run(scenario: String) -> void:
	if not require(ArcadeTrace.path(scenario), "run tools/research/arcade_fight_harness.py first"):
		return
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	if not Assets.arcade_only():
		skip("not a conversion from the arcade set")
		return
	var trace := ArcadeTrace.load_scenario(scenario)
	if trace == null:
		expect(false, "%s does not load" % scenario)
		return
	if _content == null:
		_content = ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
	var sim := ArcadeSimulation.new(_content, null, RuleSet.original())
	sim.match_choice = _choice(trace)
	_seed(sim, trace)
	_compare(scenario, trace, sim)


## The match as the program set it up: what the flow's choices left in RAM at the end of the trace.
func _choice(trace: ArcadeTrace) -> ArcadeSimulation.Match:
	var s: Dictionary = trace.header["scenario"]
	var last := trace.frames - 1
	var m := ArcadeSimulation.Match.new()
	m.mode = trace.ram(0, GAME_MODE, 2)
	m.chars = PackedInt32Array([trace.ram(last, CHARS, 2), trace.ram(last, CHARS + 2, 2)])
	m.costumes = PackedInt32Array([trace.ram(last, COSTUMES, 2), trace.ram(last, COSTUMES + 2, 2)])
	m.cpu = PackedInt32Array()
	for i in 2:
		m.cpu.append(1 if trace.read(trace.record(last, i) + CONTROL, -2) >= FIRST_CPU_CONTROL else 0)
	m.stage = s["stage"]
	m.rounds = trace.ram(0, ROUNDS, 1)
	m.round_time = trace.ram(0, ROUND_TIME, -4)
	m.neutral_guard = trace.ram(0, NEUTRAL_GUARD, 1)
	m.cpu_group = trace.ram(0, CPU_GROUP, -4)
	m.one_player_table = m.cpu_group == 1
	m.joined = trace.ram(0, JOINED, 1)
	m.life = trace.ram(0, LIFE_VERSUS if m.joined == BOTH_JOINED else LIFE_ONE, 2)
	m.start_locked = trace.ram(0, START_LOCKED, 2)
	m.difficulty = trace.ram(last, DIFFICULTY, 2)
	m.level = trace.ram(last, LEVEL, 1)
	m.attract = trace.ram(last, ATTRACT, 2)
	return m


## The first frame's work needs no generator: its state is read after that frame.
func _seed(sim: ArcadeSimulation, trace: ArcadeTrace) -> void:
	var fight := sim.fight
	fight.frame_counter = trace.ram(0, MAIN_FRAMES, 4)
	fight.camera_rng = trace.ram(0, CAMERA_RNG, 4)
	fight.frame_rng = trace.ram(0, FRAME_RNG, 4)
	fight.ai_rng = trace.ram(0, LCG, 4)
	var anim := sim.animation as ArcadeAnimation
	for k in 3:
		anim.root_channels[k] = trace.ram(0, ROOT_CHANNELS + 2 * k, -2)
	(sim.ai as ArcadeCpu).last_step = trace.ram(0, STEP, -4)


func _record_differences(rec: ArcadeAiRecord, trace: ArcadeTrace, frame: int, index: int) -> PackedStringArray:
	var out := PackedStringArray()
	var at := RECORDS + index * RECORD_BYTES
	for name: String in S32_FIELDS:
		var expected := trace.ram(frame, at + (S32_FIELDS[name] as int), -4)
		var actual: int = rec.get(name)
		if actual != expected:
			out.append("%s: %d ≠ %d" % [name, actual, expected])
	for name: String in MOVE_FIELDS:
		var expected := trace.ram(frame, at + (MOVE_FIELDS[name] as int), 4)
		var actual := ArcadeCpu.row_address(rec.get(name) as MoveRow)
		if actual != expected:
			out.append("%s: %x ≠ %x" % [name, actual, expected])
	for name: String in LIST_FIELDS:
		var offsets: Array = LIST_FIELDS[name]
		var list: PackedInt32Array = rec.get(name)
		var size := trace.ram(frame, at + (offsets[0] as int), -4)
		if list.size() != size:
			out.append("%s size: %d ≠ %d" % [name, list.size(), size])
			continue
		for k in size:
			var expected := trace.ram(frame, at + (offsets[1] as int) + 4 * k, 4)
			if _branch_address(list[k]) != expected:
				out.append("%s %d: %x ≠ %x" % [name, k, _branch_address(list[k]), expected])
	for pair: Array in [[rec.frame_count, FRAME_COUNT_AT], [rec.pad, PAD_AT], [rec.prev_pad, PREV_PAD_AT]]:
		var expected := trace.ram(frame, at + (pair[1] as int), 2)
		if (pair[0] as int) != expected:
			out.append("+0x%x: %x ≠ %x" % [pair[1], pair[0], expected])
	var throw_row := trace.ram(frame, at + THROW_ROW_AT, 4)
	if (_branch_address(rec.throw_row) if rec.throw_row >= 0 else 0) != throw_row:
		out.append("throw_row: %d ≠ %x" % [rec.throw_row, throw_row])
	if rec.script_pending() != (trace.ram(frame, at + SCRIPT_AT, 4) != 0):
		out.append("script pending: %s" % rec.script_pending())
	if (rec.hook_opponent != AiTables.Hook.NONE) != (trace.ram(frame, at + HOOK_OPPONENT_AT, 4) != 0):
		out.append("hook A: %s" % rec.hook_opponent)
	if (rec.hook_own != AiTables.Hook.NONE) != (trace.ram(frame, at + HOOK_OWN_AT, 4) != 0):
		out.append("hook B: %s" % rec.hook_own)
	if rec.filter_no_lows != (trace.ram(frame, at + FILTER_AT, 4) != 0):
		out.append("no-lows filter: %s" % rec.filter_no_lows)
	for k in ArcadeAiRecord.HISTORY:
		var expected := trace.ram(frame, at + HISTORY_AT + 4 * k, 4)
		if rec.history[k] != expected:
			out.append("history %d: %x ≠ %x" % [k, rec.history[k], expected])
	var breath := trace.ram(frame, at + OPP_BREATH_AT, 4)
	if rec.opp_breath != breath:
		out.append("opp_breath: %x ≠ %x" % [rec.opp_breath, breath])
	for offset: int in ALWAYS_ZERO:
		if trace.ram(frame, at + offset, 4) != 0:
			out.append("+0x%x is not 0" % offset)
	_words(out, "params", rec.params, trace, frame, at + PARAMS_AT)
	_words(out, "own bands", rec.own_bands, trace, frame, at + OWN_BANDS_AT)
	_words(out, "opponent's bands", rec.opp_bands, trace, frame, at + OPP_BANDS_AT)
	return out


func _words(out: PackedStringArray, label: String, actual: PackedInt32Array, trace: ArcadeTrace, frame: int, at: int) -> void:
	var expected := PackedInt32Array()
	for k in actual.size():
		expected.append(trace.ram(frame, at + 2 * k, -2))
	if actual != expected:
		out.append("%s: %s ≠ %s" % [label, actual, expected])


static func _branch_address(index: int) -> int:
	return BRANCH_ROWS + BRANCH_ROW_BYTES * index


## The table's rows up to the record's count, which the last CPU to think left.
func _candidate_differences(cpu: ArcadeCpu, count: int, trace: ArcadeTrace, frame: int) -> PackedStringArray:
	var out := PackedStringArray()
	if not trace.has_ram(CANDIDATES, CANDIDATE_BYTES * count):
		return out
	for i in count:
		var at := CANDIDATES + CANDIDATE_BYTES * i
		var row := trace.ram(frame, at + CANDIDATE_ROW, 4)
		var target := trace.ram(frame, at + CANDIDATE_TARGET, 4)
		var marked := trace.ram(frame, at + CANDIDATE_MARK, -2)
		if _branch_address(cpu.cand_index[i]) != row:
			out.append("candidate %d row: %x ≠ %x" % [i, _branch_address(cpu.cand_index[i]), row])
		if ArcadeCpu.row_address(cpu.cand_target[i]) != target:
			out.append("candidate %d target: %x ≠ %x" % [i, ArcadeCpu.row_address(cpu.cand_target[i]), target])
		if cpu.cand_mark[i] != marked:
			out.append("candidate %d mark: %d ≠ %d" % [i, cpu.cand_mark[i], marked])
	return out


func _compare(scenario: String, trace: ArcadeTrace, sim: ArcadeSimulation) -> void:
	var compare := ArcadeFighterCompare.new(trace)
	var banks: Array[MotionBank] = [_content.common]
	var cpu := sim.ai as ArcadeCpu
	var started := false
	for frame in trace.frames:
		var sub := trace.sub_state(frame)
		if frame == 0:
			sim.panels.read(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		else:
			sim.begin_panels(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		sim.flow_step(sub)
		if frame == 0:
			sim.fight.rng.state = trace.rand(0)     # the state past the first frame's load and its draws
		if sub == ArcadeSimulation.SUB_ROUND:
			started = true
		if not started:
			continue
		var lines := PackedStringArray()
		for i in 2:
			for d in compare.differences(sim.fight.fighters[i], frame, i, banks):
				lines.append("fighter %d %s" % [i, d])
			for d in _record_differences(cpu.arcade_records[i], trace, frame, i):
				lines.append("record %d %s" % [i, d])
		if sim.fight.rng.state != trace.rand(frame):
			lines.append("rand state: %d ≠ %d" % [sim.fight.rng.state, trace.rand(frame)])
		if sim.fight.ai_rng != trace.ram(frame, LCG, 4):
			lines.append("LCG: %x ≠ %x" % [sim.fight.ai_rng, trace.ram(frame, LCG, 4)])
		if cpu.last_step != trace.ram(frame, STEP, -4):
			lines.append("step: %d ≠ %d" % [cpu.last_step, trace.ram(frame, STEP, -4)])
		if sub == ArcadeSimulation.SUB_FIGHT and cpu.r != null:
			lines.append_array(_candidate_differences(cpu, cpu.r.candidate_count, trace, frame))
		if not lines.is_empty():
			var shown := lines.slice(0, MAX_REPORTED)
			expect(false, "%s frame %d of %d (sub-state %d, round state %d):\n    %s" % [scenario, frame, trace.frames,
				sub, sim.fight.round_state, "\n    ".join(shown)])
			return
