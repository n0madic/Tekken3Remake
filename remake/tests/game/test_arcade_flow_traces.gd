extends TestSuite
## Matches against the arcade program's whole game (`work/traces/arcade_flow_<scenario>.bin`,
## tools/research/arcade_flow_trace.py): the same panel words frame by frame, then the game flow's
## state compared with the program's globals, and the fighters' skeletons wherever a fight or a scene
## is shown. Needs a conversion from MAME's set alone; skipped otherwise. A scenario that empties a
## player's health (`ko_side`) has the same done to the port, on the same frame.

const SLOW := true
const MAX_REPORTED := 30
const FRAME_RNG := 0x8021F838
const MAX_SPANS := 12
const MAIN_FRAMES := 0x8021FD58
const ROUND_FIGHTING := 1               ## 0x8021F0C0 while the round is fought
const KO_AFTER := 120                   ## arcade_flow_trace.py's default, for traces without it
const DAY := 0x802F4B8C
const FLOW := {
	"state": [0x8021FD20, -4],
	"sub": [0x8021FD64, -4],
	"timer": [0x8021FD4C, -4],
	"attract_step": [0x8021F231, 1],
	"attract_previous": [0x8021F232, 1],
	"picture": [0x8021F288, -4],
	"transition_ready": [0x8021F22C, 1],
	"transition_target": [0x8021F22D, 1],
	"transition_from": [0x8021F22E, 1],
	"mode": [0x80374F18, -4],
	"flags": [0x80374F1C, 2],
	"return_state": [0x80374F1E, 1],
	"return_sub": [0x80374F1F, 1],
	"attract_silent": [0x8021FC64, 2],
}
const PAIRS := {
	"active": 0x8021FD18,
	"chosen": 0x8021FCF8,
	"cpu_control": 0x8021FB58,
	"chars": 0x8021FBF0,
	"costumes": 0x8021FC0C,
	"plays": 0x8021FC74,
	"loser_timer": 0x8021FB4C,
}
const MATCH := {
	"continues": [0x80374F24, 2],
	"joins": [0x80374F26, 2],
	"stage": [0x80374F30, 1],
	"stage_music": [0x80374F31, 1],
	"humans": [0x80374F32, 1],
	"joined": [0x80374F33, 1],
	"human_index": [0x80374F34, 1],
	"cpu_index": [0x80374F35, 1],
	"rounds": [0x80374F36, 1],
	"fight_number": [0x80374F3C, 4],
	"versus_count": [0x80374F40, 4],
	"level": [0x8021FD40, 1],
	"lead": [0x8021FCC0, 1],
	"other": [0x8021FDFC, 1],
	"win_streak": [0x8021FBE4, 2],
	"previous_time": [0x80374F48, 4],
	"total_time": [0x80374F4C, 4],
	"continue_digit": [0x8021F868, 2],
	"continue_part": [0x8021F86C, 2],
	"in_continue": [0x8021FCE4, 2],
}
const RANKING := {
	"kind": [0x80375024, 2],
	"layer": [0x80375184, 2],
	"scroll": [0x80375186, -2],
	"scroll_target": [0x80375188, -2],
	"page_clock": [0x8037518A, 2],
	"hold": [0x8037518C, 2],
	"row_rise": [0x8037518E, 2],
	"row_count": [0x80375190, 2],
}
const PROGRESS := {
	"unlocked": [0x8021FD60, 4],
	"costumes": [0x8021FD6C, 4],
}
const LADDER := 0x80374FA8
const TIME_RECORDS := 0x80375034
const WINS_RECORDS := 0x803750E4
const RECORD_BYTES := 8
const RECORD_NAME_AT := 4
const RECORD_NAME_BYTES := 4
const SELECT := 0x802C8300
const SELECT_FIELDS := {
	"mode": [0, 4],
	"two_rows": [4, 4],
	"frame": [8, 4],
	"time": [0xC, -4],
	"time_step": [0x10, 4],
	"mask": [0x28, 4],
	"count": [0x2C, 4],
	"music_delay": [0x30, 4],
}
const SPARKS := SELECT + 0x168
const SPARK_BYTES := 0x14
const SPARK_FIELDS := {
	"active": [0, 2],
	"started": [2, 2],
	"x": [4, -2],
	"y": [6, -2],
	"first_y": [8, 2],
	"start": [0xA, 2],
	"brightness": [0xC, -4],
	"fade": [0x10, 4],
}
const FIGHTERS := [0x8031E154, 0x8031FC38]
const JOINTS_AT := 0x75C
const JOINT_BYTES := 0x50
const JOINT_T_WORDS := 3
const WORD := 4
const SELECT_SIDE := 0x34
const SELECT_SIDE_BYTES := 0x80
const SIDE_FIELDS := {
	"state": [0, 4],
	"cell": [4, 4],
	"row": [8, 4],
	"rest": [0xC, 4],
	"anim_a": [0x10, 4],
	"anim_b": [0x14, 4],
	"character": [0x24, 4],
	"costume": [0x28, 4],
	"chosen_wait": [0x2C, -4],
	"chosen_anim": [0x34, 4],
	"kept_character": [0x40, 4],
	"kept_costume": [0x44, 4],
}

## A side without a cursor leaves these as they were in memory.
const CURSOR := ["cell", "row"]

var _content: ArcadeFightContent
var _data: ArcadeFlowData
var _compared_skeletons := 0
var _knock_out_clock := 0
var _bodies: Array[FighterBody] = [null, null]
var _loaded_root: Array[JointFrame] = [null, null]   ## the joint a model's load left, until a frame replaces it


func test_solo() -> void:
	_run("solo")


func test_attract() -> void:
	_run("attract")


func test_continued() -> void:
	_run("continued")


func test_challenger() -> void:
	_run("challenger")


func test_ladder() -> void:
	_run("ladder")


func _run(scenario: String) -> void:
	if not require(ArcadeFlowTrace.path(scenario), "run tools/research/arcade_flow_trace.py first"):
		return
	if not require(AssetCatalog.ROOT.path_join("tables/arcade_flow.json")):
		return
	if not Assets.arcade_only():
		skip("not a conversion from the arcade set")
		return
	var trace := ArcadeFlowTrace.load_scenario(scenario)
	if trace == null:
		expect(false, "%s does not load" % scenario)
		return
	if _content == null:
		_content = ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
		_data = ArcadeFlowData.load_from(AssetCatalog.ROOT.path_join("tables/arcade_flow.json"))
	var head: Dictionary = trace.header["scenario"]
	var flow := ArcadeGameFlow.new(_content, _data, RuleSet.original(), ArcadeSettings.new(), head["seed"] as int)
	flow.progress.day = trace.ram(0, DAY, 2)    # what the game ran with (older recordings lost the scenario's day)
	flow.progress.apply_schedule(_data)
	_compare(scenario, trace, flow)


func _compare(scenario: String, trace: ArcadeFlowTrace, flow: ArcadeGameFlow) -> void:
	var seen := {}
	_compared_skeletons = 0
	var fight := flow.fight
	var head: Dictionary = trace.header["scenario"]
	_knock_out_clock = 0
	_bodies = [null, null]
	_loaded_root = [null, null]
	fight.frame_counter = trace.ram(0, MAIN_FRAMES, 4) - 1
	fight.rng.set_seed(trace.rand(0))
	for frame in trace.frames:
		if frame > 0:
			fight.rng.state = trace.rand(frame - 1)
		_knock_out(flow, head)
		flow.step(trace.pad(frame, 0), trace.pad(frame, 1))
		_note_loads(flow)
		# Each field's first difference: the later ones follow from it.
		var fresh := PackedStringArray()
		var differences := _differences(trace, flow, frame)
		if fight.rng.state != trace.rand(frame):
			differences.append("rand: %d ≠ %d" % [fight.rng.state, trace.rand(frame)])
		if fight.frame_rng != trace.ram(frame, FRAME_RNG, 4):
			differences.append("frame generator: %d ≠ %d" % [fight.frame_rng, trace.ram(frame, FRAME_RNG, 4)])
		_fighters(differences, trace, flow, frame)
		for d in differences:
			var field := d.get_slice(":", 0)
			if not seen.has(field):
				seen[field] = PackedInt32Array([frame, frame, 0])
				fresh.append(d)
			var span: PackedInt32Array = seen[field]
			span[1] = frame
			span[2] += 1
			seen[field] = span
		if not fresh.is_empty():
			expect(false, "%s frame %d (state %d sub %d): %s" % [scenario, frame, trace.state(frame), trace.sub_state(frame), ", ".join(fresh)])
			if seen.size() >= MAX_REPORTED:
				break
	_report_spans(scenario, seen)
	expect(_compared_skeletons > 0, "%s: no skeleton was compared" % scenario)


## How far each difference went: its first and last frames and how many.
func _report_spans(scenario: String, seen: Dictionary) -> void:
	var worst := PackedStringArray()
	for field: String in seen:
		var span: PackedInt32Array = seen[field]
		if span[2] > 1:
			worst.append("%s %d..%d (%d)" % [field, span[0], span[1], span[2]])
	if not worst.is_empty():
		expect(false, "%s frames: %s" % [scenario, ", ".join(worst.slice(0, MAX_SPANS))])


## The harness's knock-out (arcade_flow_trace.py, `Driver._knock_out`), before the frame like its
## pads: the scenario's loser has no health left `ko_after` frames into each round.
func _knock_out(flow: ArcadeGameFlow, head: Dictionary) -> void:
	var side := head.get("ko_side", -1) as int
	if side < 0 or flow.state != ArcadeGameFlow.State.MATCH or flow.sub != ArcadeMatchFlow.Sub.FIGHT:
		return
	if flow.fight.round_state != ROUND_FIGHTING:
		_knock_out_clock = 0
		return
	_knock_out_clock += 1
	if _knock_out_clock == head.get("ko_after", KO_AFTER) as int:
		flow.fight.fighters[side].health = 0


func _differences(trace: ArcadeFlowTrace, flow: ArcadeGameFlow, frame: int) -> PackedStringArray:
	var out := PackedStringArray()
	_fields(out, trace, frame, flow, FLOW, "")
	_fields(out, trace, frame, flow.match_flow, MATCH, "")
	_fields(out, trace, frame, flow.progress, PROGRESS, "progress ")
	for name: String in PAIRS:
		var address: int = PAIRS[name]
		var values: PackedInt32Array = flow.get(name)
		for p in 2:
			var expected := trace.ram(frame, address + 2 * p, 2)
			if values[p] != expected:
				out.append("%s[%d]: %d ≠ %d" % [name, p, values[p], expected])
	if flow.state == ArcadeGameFlow.State.SELECT and flow.sub >= 3:
		_select(out, trace, frame, flow.select)
	if flow.state == ArcadeGameFlow.State.RANKING and flow.sub > 0:
		_fields(out, trace, frame, flow.ranking, RANKING, "ranking ")
	_records(out, trace, frame, flow.progress)
	return out


## The skeletons where the game shows them: the frames' results, so they need no replay of the flow.
func _fighters(out: PackedStringArray, trace: ArcadeFlowTrace, flow: ArcadeGameFlow, frame: int) -> void:
	if not flow.showing_fight():
		return
	for i in 2:
		var f := flow.fight.fighters[i]
		# Between a new model and its first frame the skeleton is the record's memory of older fights.
		if f.body == null or is_same(f.body.joints[0], _loaded_root[i]):
			continue
		_compared_skeletons += 1
		var rows: Array[int] = []
		rows.assign(range(FighterBody.JOINTS))
		for a: CharacterModel.ArcadeAttachment in f.body.model.arcade_attachments:
			rows.append(a.joint - CharacterModel.ARCADE_JOINT + ArcadeBody.FIRST_ROW)
		var base: int = FIGHTERS[i] + JOINTS_AT
		for row in rows:
			var wrong := _joint(trace, frame, f.body.joints[row], base + row * JOINT_BYTES)
			if not wrong.is_empty():
				out.append("fighter %d skeleton: row %d %s" % [i, row, wrong])
				break


## A new body for a fighter: its joints are not compared until a frame poses it.
func _note_loads(flow: ArcadeGameFlow) -> void:
	for i in 2:
		var body := flow.fight.fighters[i].body
		if body != _bodies[i]:
			_bodies[i] = body
			_loaded_root[i] = body.joints[0] if body != null else null


## The joint's difference from the game's, if any.
func _joint(trace: ArcadeFlowTrace, frame: int, joint: JointFrame, at: int) -> String:
	var expected := PackedInt32Array()
	for k in JOINT_T_WORDS:
		expected.append(trace.ram(frame, at + k * WORD, -WORD))
	return "" if joint.t == expected else "%s ≠ %s" % [joint.t, expected]


func _records(out: PackedStringArray, trace: ArcadeFlowTrace, frame: int, progress: ArcadeProgress) -> void:
	for i in Character.COUNT:
		var row: ArcadeProgress.Row = progress.times[i]
		var at := TIME_RECORDS + i * RECORD_BYTES
		var value := trace.ram(frame, at, 4)
		if row.value != value:
			out.append("time record %d: %d ≠ %d" % [i, row.value, value])
		_record_name(out, trace, frame, at, row, "time record %d name" % i)
	for i in ArcadeProgress.WINS_ROWS:
		var row: ArcadeProgress.Row = progress.wins[i]
		var at := WINS_RECORDS + i * RECORD_BYTES
		var value := trace.ram(frame, at, 2)
		var count := trace.ram(frame, at + 2, 2)
		if row.value != value or row.count != count:
			out.append("wins record %d: %d, %d ≠ %d, %d" % [i, row.value, row.count, value, count])
		_record_name(out, trace, frame, at, row, "wins record %d name" % i)


func _record_name(out: PackedStringArray, trace: ArcadeFlowTrace, frame: int, at: int, row: ArcadeProgress.Row, label: String) -> void:
	var expected := ""
	for letter in RECORD_NAME_BYTES:
		var code := trace.ram(frame, at + RECORD_NAME_AT + letter, 1)
		if code == 0:
			break
		expected += char(code)
	if row.name != expected:
		out.append("%s: %s ≠ %s" % [label, row.name, expected])


func _select(out: PackedStringArray, trace: ArcadeFlowTrace, frame: int, select: ArcadeSelect) -> void:
	_offset_fields(out, trace, frame, select, SELECT_FIELDS, SELECT, "select ")
	for p in 2:
		_side(out, trace, frame, select.sides[p], p)
	for i in SelectSparks.COUNT:
		var spark: SelectSparks.Spark = select.sparks.sparks[i]
		var at := SPARKS + i * SPARK_BYTES
		if spark.active != 0 or trace.ram(frame, at, 2) != 0:
			_offset_fields(out, trace, frame, spark, SPARK_FIELDS, at, "spark %d " % i)


func _side(out: PackedStringArray, trace: ArcadeFlowTrace, frame: int, side: ArcadeSelectSide, p: int) -> void:
	var base := SELECT + SELECT_SIDE + p * SELECT_SIDE_BYTES
	for name: String in SIDE_FIELDS:
		if name in CURSOR and side.state == ArcadeSelect.PlayerState.CPU:
			continue
		var g: Array = SIDE_FIELDS[name]
		var expected := trace.ram(frame, base + (g[0] as int), g[1] as int)
		var actual: int = side.get(name)
		if actual != expected:
			out.append("select side %d %s: %d ≠ %d" % [p, name, actual, expected])


func _fields(out: PackedStringArray, trace: ArcadeFlowTrace, frame: int, owner: Object, fields: Dictionary, label: String) -> void:
	for name: String in fields:
		var g: Array = fields[name]
		var expected := trace.ram(frame, g[0] as int, g[1] as int)
		var actual: int = owner.get(name)
		if actual != expected:
			out.append("%s%s: %d ≠ %d" % [label, name, actual, expected])


func _offset_fields(out: PackedStringArray, trace: ArcadeFlowTrace, frame: int, owner: Object, fields: Dictionary, base: int, label: String) -> void:
	for name: String in fields:
		var g: Array = fields[name]
		var expected := trace.ram(frame, base + (g[0] as int), g[1] as int)
		var actual: int = owner.get(name)
		if actual != expected:
			out.append("%s%s: %d ≠ %d" % [label, name, actual, expected])
