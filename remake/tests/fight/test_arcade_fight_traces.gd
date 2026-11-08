extends TestSuite
## Matches against the arcade program's own fight code (`work/traces/arcade_<scenario>.bin`,
## tools/research/arcade_fight_harness.py): the same panel words frame by frame, then every fighter
## field and the fight's globals compared with the game's records. Needs a conversion from MAME's set
## alone (`manifest.source` "arcade"); skipped otherwise.

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
const ATTRACT_FIGHTS := 0x8021F39C
const MODE := 0x80374F18
const CONTROL := 0x34A
const FIRST_CPU_CONTROL := 3            ## +0x34A: a human's is its player + 1, a CPU's its player + 3
const UNLOCKED := 0x8021FD60            ## Mokujin's moves are one of these
const WIND := 0x8021F690
const WIND_PHASE := 8
const COMPARED := {
	"camera_phase": [0x8021FCD0, -4],
	"camera_rng": [CAMERA_RNG, 4],
	"round_state": [0x8021F0C0, -4],
	"round_counter": [0x8021F0C4, -4],
	"round_frame": [0x8021FD88, -4],
	"timer": [0x8021FB8C, -4],
	"no_damage": [0x8021FC4C, -4],
	"replay_playing": [0x8021F03C, -4],
	"blend_hold": [0x8021FB50, -4],
}
const COMPARED_REPLAY := {
	"mode": [0x8021F640, -4],
	"record": [0x8021F650, -4],
	"play": [0x8021F654, -4],
	"mark": [0x8021F658, -4],
	"skip": [0x8021F660, -4],
	"recorded": [0x8021F668, -4],
}
const INPUT_MODES := 0x8021FAE4
## 0x802C6BD4: the camera's view, read after FUN_801AE9DC added the shake.
const VIEW := {"pitch": [0x802C6BD4, -4], "yaw": [0x802C6BD8, -4], "roll": [0x802C6BDC, -4], "x": [0x802C6BE8, -4],
	"y": [0x802C6BEC, -4], "z": [0x802C6BF0, -4], "h": [0x8021FAF4, -4]}
const DIRECTOR := {
	"state": [0x802F4B98, -4],
	"enabled": [0x8021FB9C, -4],
	"thrower": [0x802F4BC8, -4],
	"side": [0x802F4BCC, -4],
	"wait": [0x802F4BD0, -4],
	"count": [0x802F4BD4, -4],
	"count_total": [0x802F4BD8, -4],
	"throw_player": [0x802F4BDC, -4],
	"switch_mode": [0x802F4BE0, -4],
	"hit_count": [0x802F4BE4, -4],
	"hit_total": [0x802F4BE8, -4],
	"cam_script": [0x802F4BEC, -4],
	"script_kind": [0x802F4BF0, -4],
	"choice_index": [0x802F4BF4, -4],
	"preset_pitch": [0x802F4BFC, -4],
	"preset_yaw": [0x802F4C00, -4],
	"stream_frame": [0x802F4C08, -4],
	"mirror": [0x802F4C24, -4],
	"h": [0x802F4C28, -4],
	"h_min": [0x802F4C2C, -4],
	"h_max": [0x802F4C30, -4],
	"stream_rescale": [0x802F4C34, -4],
	"stage_mode": [0x802F4C38, -4],
	"stream_restart": [0x802F4C3C, -4],
	"skip_side": [0x802F4C44, -4],
	"height_term": [0x8021F3A8, -4],
	"intro_counter": [0x8021F3C4, -4],
	"replay_on": [0x8021F3DC, -4],
	"loser_height": [0x8021F90C, -4],
	"loser_yaw": [0x8021F910, -4],
	"intro_timer": [0x802A10C4, -2],
	"intro_length": [0x802A10C6, -2],
	"intro_index": [0x802A10C8, -2],
	"replay_style": [0x802A1108, -4],
	"replay_reset": [0x802A110C, -4],
	"replay_pitch": [0x802A1114, -4],
	"replay_swing": [0x802A111C, -4],
	"replay_swing_to": [0x802A1120, -4],
	"replay_distance": [0x802A1124, -4],
	"replay_yaw": [0x802A1128, -4],
	"replay_track": [0x802A112C, -4],
	"replay_count": [0x802A1130, -4],
}
const WEIGHTS := 0x802F4B9C
const PREVIOUS_WEIGHTS := 0x802F4BB0
const STREAM_ORIGIN := 0x802F4C10
const SOURCES := 0x8029DE44
const SOURCE_BYTES := 0x1C
const SOURCE_WORDS := [0, 4, 8, 0xC, 0x10, 0x18]         ## x, y, z, pitch, yaw, H (+0x14: the roll, below)
const SOURCE_ROLL := 0x14
const SOURCE_STATES := 0x8029DEF8
const SOURCE_STATE_BYTES := 0x3C
## The fields of a source's framing state; +0x1C is a counter nothing reads, not kept.
const SOURCE_STATE := {"phase": 0, "angle": 4, "speed": 8, "pitch": 0xC, "pitch_target": 0x10, "pitch_step": 0x14,
	"error": 0x18, "frames": 0x20, "moved": 0x24, "depth_step": 0x28, "depth": 0x2C, "lateral": 0x30,
	"cleared_a": 0x34, "cleared_b": 0x38}
const TARGETS := 0x80374FD8
const PREVIOUS_TARGETS := 0x8036EB94
const TARGET_BYTES := 0x10
const SCREEN_TARGETS := 0x8021FBAC
const PREVIOUS_SCREEN_TARGETS := 0x8021FDD4
const STREAM_SAMPLE := 0x8029E074
const SAMPLE_OFFSETS := [0, 2, 4, 8, 0xA, 0xC]           ## eye, target (s16)
const SAMPLE_WEIGHT := 0x8029E084
const SAMPLE_H := 0x8029E088
const HIT_POINT := 0x802A1098
const INTRO_BASE := 0x802A10CC
const LOSER := 0x802A10E8
const REPLAY_TARGETS := 0x802A1134
const WINNER := 0x8025E584
const WINNER_WORDS := [0, 1, 5, 6, 7]                    ## pitch, yaw, eye
const VIEW_MATRIX := 0x8036EBFC
const VIEW_MATRIX_T := 0x8036EC10

var _content: ArcadeFightContent


func test_probe() -> void:
	_run("probe")


func test_camera_stage1() -> void:
	_run("camera_stage1")


func test_camera_stage3() -> void:
	_run("camera_stage3")


func test_camera_stage4() -> void:
	_run("camera_stage4")


func test_camera_stage5() -> void:
	_run("camera_stage5")


func test_camera_stage10() -> void:
	_run("camera_stage10")


func test_camera_rounds() -> void:
	_run("camera_rounds")


func test_camera_match() -> void:
	_run("camera_match")


func test_camera_time_up() -> void:
	_run("camera_time_up")


func test_camera_throws_king() -> void:
	_run("camera_throws_king")


func test_camera_throws_nina() -> void:
	_run("camera_throws_nina")


func test_camera_throws_paul() -> void:
	_run("camera_throws_paul")


func test_camera_throws_yoshimitsu() -> void:
	_run("camera_throws_yoshimitsu")


func test_camera_throws_hwoarang() -> void:
	_run("camera_throws_hwoarang")


func test_camera_throws_low() -> void:
	_run("camera_throws_low")


func test_camera_chain_king_a() -> void:
	_run("camera_chain_king_a")


func test_camera_chain_king_b() -> void:
	_run("camera_chain_king_b")


func test_camera_chain_king_second() -> void:
	_run("camera_chain_king_second")


func test_camera_throws_second_king() -> void:
	_run("camera_throws_second_king")


func test_camera_throws_second_nina() -> void:
	_run("camera_throws_second_nina")


func test_camera_chain_king_b_second() -> void:
	_run("camera_chain_king_b_second")


func test_camera_breaks() -> void:
	_run("camera_breaks")


func test_camera_breaks_second() -> void:
	_run("camera_breaks_second")


func test_camera_law_up() -> void:
	_run("camera_law_up")


func test_camera_paul_down() -> void:
	_run("camera_paul_down")


func test_camera_law_back() -> void:
	_run("camera_law_back")


func test_camera_back_king() -> void:
	_run("camera_back_king")


func test_camera_paul_arm() -> void:
	_run("camera_paul_arm")


func test_camera_paul_sway() -> void:
	_run("camera_paul_sway")


func test_camera_paul_smash() -> void:
	_run("camera_paul_smash")


func test_camera_jin_step() -> void:
	_run("camera_jin_step")


func test_camera_throws_both() -> void:
	_run("camera_throws_both")


func test_camera_loser() -> void:
	_run("camera_loser")


func test_camera_loser_time() -> void:
	_run("camera_loser_time")


func test_camera_attract_free() -> void:
	_run("camera_attract_free")


func test_camera_attract_orbit() -> void:
	_run("camera_attract_orbit")


func test_camera_attract_sweep() -> void:
	_run("camera_attract_sweep")


func test_camera_attract_low() -> void:
	_run("camera_attract_low")


func test_camera_attract_lowest() -> void:
	_run("camera_attract_lowest")


func test_camera_attract_lowest_orbit() -> void:
	_run("camera_attract_lowest_orbit")


## Stage 11 in a match: the wind blows the attachments, and a round starts its gust again.
func test_wind_stage11() -> void:
	_run("wind_stage11")


## Mokujin takes a character's moves each round.
func test_mokujin() -> void:
	_run("mokujin")


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


func _choice(trace: ArcadeTrace) -> ArcadeSimulation.Match:
	var s: Dictionary = trace.header["scenario"]
	var last := trace.frames - 1
	var m := ArcadeSimulation.Match.new()
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
	m.mode = trace.ram(last, MODE, -4)
	return m


## The first frame's load draws the wind's direction from `rand` as it stood before that frame.
func _seed(sim: ArcadeSimulation, trace: ArcadeTrace) -> void:
	var fight := sim.fight
	fight.frame_counter = trace.ram(0, MAIN_FRAMES, 4)
	fight.camera_rng = trace.ram(0, CAMERA_RNG, 4)
	fight.frame_rng = trace.ram(0, FRAME_RNG, 4)
	fight.rng.set_seed(trace.header.get("rand_start", trace.rand(0)) as int)
	(sim.camera as ArcadeCamera).attract_counter = trace.ram(0, ATTRACT_FIGHTS, -4)
	fight.unlocked = trace.ram(0, UNLOCKED, 4)
	var anim := sim.animation as ArcadeAnimation
	for k in 3:
		anim.root_channels[k] = trace.ram(0, ROOT_CHANNELS + 2 * k, -2)


func _globals(sim: ArcadeSimulation, trace: ArcadeTrace, frame: int) -> PackedStringArray:
	var out := PackedStringArray()
	for pair: Array in [[COMPARED, sim.fight, ""], [COMPARED_REPLAY, sim.fight.replay, "replay "]]:
		var fields: Dictionary = pair[0]
		var owner: Object = pair[1]
		for name: String in fields:
			var g: Array = fields[name]
			var expected := trace.ram(frame, g[0] as int, g[1] as int)
			var actual: int = owner.get(name)
			if actual != expected:
				out.append("%s%s: %d ≠ %d" % [pair[2], name, actual, expected])
	for i in 2:
		var expected := trace.ram(frame, INPUT_MODES + 4 * i, -4)
		if sim.fight.input_mode[i] != expected:
			out.append("input mode %d: %d ≠ %d" % [i, sim.fight.input_mode[i], expected])
	return out


func _named(out: PackedStringArray, label: String, owner: Object, fields: Dictionary, trace: ArcadeTrace, frame: int) -> void:
	for name: String in fields:
		var g: Array = fields[name]
		var expected := trace.ram(frame, g[0] as int, g[1] as int)
		var actual: int = owner.get(name)
		if actual != expected:
			out.append("%s%s: %d ≠ %d" % [label, name, actual, expected])


func _words(out: PackedStringArray, label: String, actual: PackedInt32Array, trace: ArcadeTrace, frame: int, at: int, offsets: Array, size := -4) -> void:
	var expected := PackedInt32Array()
	for offset: int in offsets:
		expected.append(trace.ram(frame, at + offset, size))
	if actual != expected:
		out.append("%s: %s ≠ %s" % [label, actual, expected])


## What the round's start leaves: the sources and their targets. The director's own state starts with its
## reset on the next frame.
func _camera_start(sim: ArcadeSimulation, trace: ArcadeTrace, frame: int) -> PackedStringArray:
	var out := PackedStringArray()
	var c := sim.camera
	for i in CameraDirector.SOURCES:
		if i != CameraDirector.SOURCE_OUTPUT and i != CameraDirector.SOURCE_TRANSITION:
			var at := SOURCES + i * SOURCE_BYTES
			_words(out, "source %d" % i, c.sources[i], trace, frame, at, SOURCE_WORDS)
			if trace.ram(frame, at + SOURCE_ROLL, -4) != 0:
				out.append("source %d has a roll" % i)
		var st := c.source_state[i]
		_named_at(out, "source state %d " % i, st, SOURCE_STATE, trace, frame, SOURCE_STATES + i * SOURCE_STATE_BYTES)
	for k in 2:
		_words(out, "target %d" % k, c.targets[k].slice(0, 3), trace, frame, TARGETS + k * TARGET_BYTES, [0, 4, 8])
		_words(out, "screen target %d" % k, c.targets[k].slice(3, 4), trace, frame, SCREEN_TARGETS + 4 * k, [0])
	_named(out, "director ", c, {"h": DIRECTOR["h"], "h_min": DIRECTOR["h_min"], "h_max": DIRECTOR["h_max"],
		"intro_timer": DIRECTOR["intro_timer"], "intro_length": DIRECTOR["intro_length"], "intro_index": DIRECTOR["intro_index"]}, trace, frame)
	_named(out, "view ", c.view, {"h": VIEW["h"]}, trace, frame)
	_words(out, "intro base", c.intro_base, trace, frame, INTRO_BASE, SOURCE_WORDS)
	return out


func _named_at(out: PackedStringArray, label: String, owner: Object, fields: Dictionary, trace: ArcadeTrace, frame: int, at: int) -> void:
	for name: String in fields:
		var expected := trace.ram(frame, at + (fields[name] as int), -4)
		var actual: int = owner.get(name)
		if actual != expected:
			out.append("%s%s: %d ≠ %d" % [label, name, actual, expected])


## The camera against the game's after a frame the director ran: nothing of it is taken from the trace.
func _camera(sim: ArcadeSimulation, trace: ArcadeTrace, frame: int) -> PackedStringArray:
	var out := _camera_start(sim, trace, frame)
	var c := sim.camera
	_named(out, "view ", c.view, VIEW, trace, frame)
	_named(out, "director ", c, DIRECTOR, trace, frame)
	_words(out, "weights", c.weights, trace, frame, WEIGHTS, [0, 4, 8, 0xC, 0x10])
	_words(out, "previous weights", c.prev_weights, trace, frame, PREVIOUS_WEIGHTS, [0, 4, 8, 0xC, 0x10])
	_words(out, "stream origin", c.stream_origin, trace, frame, STREAM_ORIGIN, [0, 4, 8])
	for i: int in [CameraDirector.SOURCE_OUTPUT, CameraDirector.SOURCE_TRANSITION]:
		_words(out, "source %d" % i, c.sources[i], trace, frame, SOURCES + i * SOURCE_BYTES, SOURCE_WORDS)
	for k in 2:
		_words(out, "previous target %d" % k, c.prev_targets[k].slice(0, 3), trace, frame, PREVIOUS_TARGETS + k * TARGET_BYTES, [0, 4, 8])
		_words(out, "previous screen target %d" % k, c.prev_targets[k].slice(3, 4), trace, frame, PREVIOUS_SCREEN_TARGETS + 4 * k, [0])
	_words(out, "stream sample", c.stream_sample.slice(0, 6), trace, frame, STREAM_SAMPLE, SAMPLE_OFFSETS, -2)
	_words(out, "stream weight and H", c.stream_sample.slice(6, 8), trace, frame, SAMPLE_WEIGHT, [0, 4])
	_words(out, "hit point", c.hit_point, trace, frame, HIT_POINT, [0, 4, 8])
	_words(out, "loser", c.loser.slice(0, 6), trace, frame, LOSER, [0, 4, 8, 0xC, 0x10, 0x14])
	# x0, y0, z0, x1: what the trace's range holds of them.
	var r := c.replay_targets
	_words(out, "replay targets", PackedInt32Array([r[0], r[2], r[4], r[1]]), trace, frame, REPLAY_TARGETS, [0, 4, 8, 0x10])
	for j in WINNER_WORDS.size():
		var word: int = WINNER_WORDS[j]
		var expected := trace.ram(frame, WINNER + word * 4, -4)
		if c.winner_a[word] != expected:
			out.append("winner word %d: %d ≠ %d" % [word, c.winner_a[word], expected])
	_view_matrix(out, sim.view, trace, frame)
	return out


## The GTE matrix of the frame (FUN_801A26A4): s16 rows and the translation.
func _view_matrix(out: PackedStringArray, m: ViewMatrix, trace: ArcadeTrace, frame: int) -> void:
	var rows := PackedInt32Array()
	for k in 9:
		rows.append(trace.ram(frame, VIEW_MATRIX + 2 * k, -2))
	if m.rot != rows:
		out.append("view matrix: %s ≠ %s" % [m.rot, rows])
	_words(out, "view translation", m.t, trace, frame, VIEW_MATRIX_T, [0, 4, 8])


## FUN_8019C738's vector and phase.
func _wind(wind: ArcadeWind, trace: ArcadeTrace, frame: int) -> PackedStringArray:
	var out := PackedStringArray()
	var expected := PackedInt32Array()
	for k in 3:
		expected.append(trace.ram(frame, WIND + 2 * k, -2))
	if wind.vector != expected:
		out.append("wind: %s ≠ %s" % [wind.vector, expected])
	if wind.phase != trace.ram(frame, WIND + WIND_PHASE, -4):
		out.append("wind phase: %d ≠ %d" % [wind.phase, trace.ram(frame, WIND + WIND_PHASE, -4)])
	return out


func _compare(scenario: String, trace: ArcadeTrace, sim: ArcadeSimulation) -> void:
	var compare := ArcadeFighterCompare.new(trace)
	var banks: Array[MotionBank] = [_content.common]
	var started := false
	for frame in trace.frames:
		var sub := trace.sub_state(frame)
		if frame == 0:
			sim.panels.read(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		else:
			sim.begin_panels(PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		# What the round's load draws is not simulated: `rand` is free from the round on.
		if frame > 0 and not started:
			sim.fight.rng.state = trace.rand(frame - 1)
		sim.flow_step(sub)
		if sub == ArcadeSimulation.SUB_ROUND:
			started = true
		if not started:
			continue
		var lines := _globals(sim, trace, frame)
		lines.append_array(_camera(sim, trace, frame) if sub == ArcadeSimulation.SUB_FIGHT else _camera_start(sim, trace, frame))
		if sim.fight.rng.state != trace.rand(frame):
			lines.append("rand state: %d ≠ %d" % [sim.fight.rng.state, trace.rand(frame)])
		lines.append_array(_wind(sim.wind, trace, frame))
		for i in 2:
			for d in compare.differences(sim.fight.fighters[i], frame, i, banks):
				lines.append("fighter %d %s" % [i, d])
		if not lines.is_empty():
			var shown := lines.slice(0, MAX_REPORTED)
			expect(false, "%s frame %d of %d (sub-state %d, round state %d):\n    %s" % [scenario, frame, trace.frames,
				sub, sim.fight.round_state, "\n    ".join(shown)])
			return
