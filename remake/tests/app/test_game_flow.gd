extends TestSuite
## The whole game against the game's own code (`work/traces/flow_<scenario>.bin`,
## tools/research/flow_trace.py): from boot with the same pads frame by frame, the game state and
## sub-state, the engine calls, the progress block, the mode region, the players' globals, the
## screens' state and, in fights, the fighters are compared with the game's.

const SLOW := true                  ## the runner's --quick leaves the trace comparisons out
const MAX_REPORTED := 30
const REFILL_RULE := 4               ## flow_trace.py's refill header: HEALTH, REFILL_BELOW, TIMER_BELOW, TIMER_REFILL
const DRAIN_RULE := 3                ## flow_trace.py's drain header: HEALTH, IS_CPU, DRAIN_TO
## The camera director's globals kept across matches, compared in every fight frame where the
## trace has them (address, size; negative: signed).
const DIRECTOR_GLOBALS := [["intro counter", 0x8009892C, -4], ["winner style", 0x800A0844, -4]]
## The panorama's turn (BackdropTurn), compared in the fight frames where the trace has it.
const BACKDROP_GLOBALS := [["backdrop angle", 0x800A9650, 4], ["backdrop prev yaw", 0x800A9658, 4],
	["backdrop yaw", 0x800A9664, 4], ["look point x", 0x800AE0D8, -4], ["look point z", 0x800AE0E0, -4]]
## The camera's view compared in these fight sub-states: the fight and the Ogre scene.
const VIEW_SUBS: Array[int] = [8, 17]
const VIEW_FIELDS := [["pitch", 0x800A8A88], ["yaw", 0x800A8A8C], ["x", 0x800A8A9C], ["y", 0x800A8AA0],
	["z", 0x800A8AA4]]
const PRACTICE_FREE_PAGE := 476      ## the practice scenario's frame on the FREE page, taking input
## Typed globals compared each frame: name, address, size (negative: signed).
const GLOBALS := [
	["char 0", 0x800AE224, 2], ["char 1", 0x800AE226, 2], ["costume 0", 0x800AE260, 2],
	["costume 1", 0x800AE262, 2], ["cpu 0", 0x800A95F0, 2], ["cpu 1", 0x800A95F2, 2],
	["active 0", 0x800AE6C0, 2], ["active 1", 0x800AE6C2, 2], ["keep 0", 0x800AE484, 2],
	["keep 1", 0x800AE486, 2], ["other player", 0x800B0A06, 1], ["win streak", 0x800AE218, 2],
	["tie choice", 0x800AE406, 1], ["save pending", 0x800AE428, 1], ["challenger lock", 0x800AE6DA, 2],
	["state timer", 0x800AE6DC, -4], ["stage", 0x800AE14C, 2], ["music", 0x800AE1D0, 2],
	["round time", 0x800AE3C0, 2], ["human mask", 0x800AE3D8, 2], ["difficulty", 0x800AE6D0, 2],
	["level", 0x800AE6D9, 1], ["attract", 0x800AE39C, 2], ["hud shown", 0x800AE6C8, 2],
	["rand", 0x800A3E80, 4], ["frame rng", 0x8009F650, 4], ["camera rng", 0x800A95F4, 4],
	["pad repeat 0", 0x800AE3C8, 2], ["pad repeat 1", 0x800AE3CA, 2],
]
## Quick select context words compared (the screen writes them; the rest holds older data): the
## mode and fade, and per record the state, cursor, available mask, team size, picks, handicap and
## last pick.
const RESULT_STATES := [GameFlow.State.TEAM_RESULT, GameFlow.State.TIME_RESULT, GameFlow.State.SURVIVAL_RESULT]
## Result screen words compared per state (the overlay's other words hold older data).
const RESULT_FIELDS := {
	GameFlow.State.TEAM_RESULT: [0x00, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x230],
	GameFlow.State.TIME_RESULT: [0x190, 0x194, 0x198, 0x19C, 0x1A0, 0x1A4, 0x1A8, 0x1AC, 0x1B0, 0x230],
	GameFlow.State.SURVIVAL_RESULT: [0x1B8, 0x1E0, 0x1E4, 0x1E8, 0x1EC, 0x1F0, 0x1F4, 0x1F8, 0x1FC, 0x200, 0x230],
}
## Ranking table fields compared (older data until the screen writes them): name, offset, size,
## the first sub-state after the field's writer.
const RANKING_FIELDS := [["mode", 0, 2, 2], ["y", 2, 2, 5], ["target", 4, 2, 6], ["hold", 6, 2, 2],
	["frames", 8, 2, 2], ["alpha", 0xA, 2, 6], ["rows", 0xC, 2, 2], ["group", 0x50, 4, 5],
	["shown", 0x54, 4, 5], ["name row", 0x86, 2, 0xB], ["entry", 0x88, 2, 2]]
const QUICK_FIELDS := [0x00, 0x08, 0x0C,
	0x18, 0x20, 0x24, 0x3C, 0x40, 0x44, 0x50, 0x70, 0x7C,
	0xC4, 0xCC, 0xD0, 0xE8, 0xEC, 0xF0, 0xFC, 0x11C, 0x128]
## Fighter fields compared in the fight state: name, offset, size.
const FIGHTER_FIELDS := [
	["charId", 0x18, -2], ["costume key", 0x14, -2], ["isCpu", 0xC5, 1], ["health", 0x3F4, -4],
	["roundWins", 0x44, -2], ["posX", 0x00, -4], ["posZ", 0x08, -4], ["poseFrame", 0x58, -2],
]

var _enbu: EnbuAssets
var _options_page := -1


func test_vs_mode() -> void:
	_run("vs_mode")


func test_arcade() -> void:
	_run("arcade")


func test_time_attack() -> void:
	_run("time_attack")


func test_survival() -> void:
	_run("survival")


func test_team_battle() -> void:
	_run("team_battle")


func test_practice() -> void:
	_run("practice")


func test_options() -> void:
	_run("options")


func test_attract() -> void:
	_run("attract")


func test_ball() -> void:
	_run("ball")


func test_ball_versus() -> void:
	_run("ball_versus")


func test_force() -> void:
	_run("force")


## Tekken Force's pick-up flash against the original (stages.md#lighting): the frame after the
## frame in which the trace's item is picked up the player is lit with the flash's count 1, and the
## count rises by one a frame to 32, then ends. The back colours are what the original's SetBackColor
## left in the GTE in the `force` scenario (`work/traces/force_back_colour.json`,
## tools/research/trace_back_colour.py: the level's light record word, then red = green and blue): they
## show while the player is the last fighter drawn (an enemy takes the register over from count 26 on).
const FORCE_BACK_COLOUR_FILE := "force_back_colour.json"
const ITEM_BYTES := 0xBC
const ITEM_PICKED_UP := 2              ## an item's state word while its LIFE UP! shows


func test_force_pickup_flash() -> void:
	if not require(TraceFiles.path(FORCE_BACK_COLOUR_FILE), "run tools/research/trace_back_colour.py force --out first"):
		return
	var golden: Dictionary = JsonFile.read(TraceFiles.path(FORCE_BACK_COLOUR_FILE))
	var ambient: int = golden["ambient"]
	var seen := {"pickup": -1, "levels": [] as Array[int], "colours": [] as Array[Vector3]}
	var watch := func(flow: GameFlow, trace: FlowTrace, frame: int) -> bool:
		var levels := seen["levels"] as Array[int]
		if seen["pickup"] as int < 0:
			for i in 2:
				if trace.ram(frame, TekkenForce.ITEMS + ITEM_BYTES * i, 4) == ITEM_PICKED_UP:
					seen["pickup"] = frame
			return false
		levels.append(flow.fight.flash_level[0])
		(seen["colours"] as Array[Vector3]).append(
			StageLighting.fighter_back_colour(ambient, flow.fight.flash_level[0], StageLighting.NO_SIGNAL))
		return levels.size() >= FighterAnimation.FLASH_FRAMES + 2
	_run("force", watch)
	if not expect(seen["pickup"] as int >= 0, "the trace picks an item up"):
		return
	var expected: Array[int] = []
	for count in range(1, FighterAnimation.FLASH_FRAMES + 1):
		expected.append(count)
	expected.append_array([0, 0])
	expect_equal(seen["levels"] as Array[int], expected, "the counts the player is lit with after the pick-up")
	var colours := seen["colours"] as Array[Vector3]
	var harness: Array = golden["colours"]
	for i in harness.size():
		var rb := JsonFile.ints(harness[i] as Array)
		expect_equal(colours[i], StageLighting.back_colour(rb[0], rb[0], rb[1]), "back colour %d frames after the pick-up" % (i + 1))


func test_force_run() -> void:
	_run("force_run")


func test_force_final() -> void:
	_run("force_final")


func test_force_bosses() -> void:
	_run("force_bosses")


func test_ogre() -> void:
	_run("ogre")


## The Ogre scene ends in a fade to white (FUN_8004E2E8 at level + 256 from frame 192, growing by
## 4 a frame) that is held at full for the last three frames, before True Ogre's fight loads.
func test_ogre_scene_fades_to_white() -> void:
	if not require(FlowTrace.path("ogre"), "run tools/research/flow_trace.py first"):
		return
	var trace := FlowTrace.load_scenario("ogre")
	var flow := imported_flow((trace.header["scenario"] as Dictionary)["seed"] as int)
	if flow == null:
		return
	if _enbu == null:
		_enbu = EnbuAssets.load_from(AssetCatalog.ROOT)
	flow.performance_factory = _enbu.performance
	for poke in trace.pokes():
		flow.progress.put8(poke[0] - GameProgress.BASE, poke[1])
	var refill: Variant = trace.header.get("refill")
	var drain: Variant = trace.header.get("drain")
	var levels := PackedInt32Array()
	var frames_in_scene := 0
	for frame in trace.frames:
		var pads := PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)])
		var in_scene := flow.state == GameFlow.State.FIGHT and flow.sub == 17
		_step_flow(flow, pads)
		if refill != null:
			_refill(flow, refill as Array)
		if drain != null:
			_drain(flow, drain as Array)
		if in_scene:
			frames_in_scene += 1
			levels.append(flow.fades[0] if not flow.fades.is_empty() else -1)
		elif frames_in_scene > 0:
			break
	if not expect(frames_in_scene > 0, "the trace reaches the Ogre scene"):
		return
	var first_fade := levels.find(0x100)
	expect(first_fade >= 0, "the fade starts at the neutral level 0x100")
	var white := levels.slice(levels.size() - 3)
	expect(white == PackedInt32Array([0x200, 0x200, 0x200]), "the scene ends in three frames of full white: %s" % white)
	var rising := true
	for i in range(first_fade + 1, levels.size()):
		rising = rising and levels[i] >= levels[i - 1]
	expect(rising, "the fade never goes back down")
	expect(levels[first_fade - 1] == -1, "no fade is drawn before the script's fade event")


## The Ogre scene draws only the fighters it stepped: none before its moves start at script frame
## 10, then both, and both again for the fight that follows.
func test_ogre_scene_draws_only_stepped_fighters() -> void:
	if not require(FlowTrace.path("ogre"), "run tools/research/flow_trace.py first"):
		return
	var trace := FlowTrace.load_scenario("ogre")
	var flow := imported_flow((trace.header["scenario"] as Dictionary)["seed"] as int)
	if flow == null:
		return
	if _enbu == null:
		_enbu = EnbuAssets.load_from(AssetCatalog.ROOT)
	flow.performance_factory = _enbu.performance
	for poke in trace.pokes():
		flow.progress.put8(poke[0] - GameProgress.BASE, poke[1])
	var drain: Variant = trace.header.get("drain")
	var masks := PackedInt32Array()
	var after := -1
	for frame in trace.frames:
		var pads := PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)])
		var in_scene := flow.state == GameFlow.State.FIGHT and flow.sub == 17
		_step_flow(flow, pads)
		if drain != null:
			_drain(flow, drain as Array)
		if in_scene or flow.sub == 17:
			masks.append(flow.fight.undrawn_mask)
		elif not masks.is_empty():
			after = flow.fight.undrawn_mask
			break
	if not expect(not masks.is_empty(), "the trace reaches the Ogre scene"):
		return
	expect_equal(masks[0], 3, "nothing is drawn when the scene starts")
	expect_equal(masks[masks.size() / 2], 0, "both fighters are drawn once their moves run")
	expect_equal(after, 0, "the fight after the scene draws both fighters")


## Practice's COMMAND LIST (MoveListScreen.practice_page) from the FREE page of the practice
## scenario, then the remake's Escape: kept through the menu's inert frames, then as OK.
func test_practice_command_list_and_escape() -> void:
	if not require(FlowTrace.path("practice"), "run tools/research/flow_trace.py first"):
		return
	var trace := FlowTrace.load_scenario("practice")
	var flow := imported_flow((trace.header["scenario"] as Dictionary)["seed"] as int)
	if flow == null:
		return
	for frame in PRACTICE_FREE_PAGE:
		_step_flow(flow, PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
	var s := flow.practice.s
	expect(s.u8(PracticeMode.PAUSED) != 0 and s.u8(PracticeMode.MENU_DELAY) == 0, "the FREE page takes input")
	var idle := PackedInt32Array([0, 0])
	var player := s.u8(PracticeMode.PLAYER)
	for pad: int in [0x4000, 0, 0x40, 0]:
		_step_flow(flow, PackedInt32Array([pad, 0] if player == 0 else [0, pad]))
	expect_equal(s.u8(PracticeMode.COMMAND_LIST), 1, "COMMAND LIST turned on")
	var shown: SimEvents.Event = null
	for i in 5:
		_step_flow(flow, idle)
		shown = flow.sim.events.first(SimEvents.Kind.MOVE_LIST)
	expect(shown != null, "the list is shown")
	if shown != null:
		expect_equal(shown.a, 1 << player, "the player's list (the dummy is not on CONTROLLER)")
	_step_flow(flow, PackedInt32Array([PadState.START, 0] if player == 0 else [0, PadState.START]))
	expect_equal(s.u8(PracticeMode.COMMAND_LIST), 0, "Start turns it off")
	expect(s.u8(PracticeMode.MENU_DELAY) != 0, "the menu is inert again")
	flow.escape_pressed = true
	_step_flow(flow, idle)
	expect(flow.escape_pressed, "Escape waits for the menu")
	for i in 6:
		_step_flow(flow, idle)
	expect(not flow.escape_pressed, "Escape taken")
	expect_equal(s.u8(PracticeMode.PAUSED), 0, "Escape leaves the menu as OK")


## Start + Select on the arcade's character select back to the main menu: loading title.ovl
## stops the select music (a disc read pauses the XA stream, FUN_8006B834).
func test_menu_exit_stops_music() -> void:
	if not require(FlowTrace.path("arcade"), "run tools/research/flow_trace.py first"):
		return
	var trace := FlowTrace.load_scenario("arcade")
	var flow := imported_flow((trace.header["scenario"] as Dictionary)["seed"] as int)
	if flow == null:
		return
	var music := -1
	var frame := 0
	while flow.state != GameFlow.State.SELECT and frame < trace.frames:
		_step_flow(flow, PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		music = _music_after(flow.sim.events, music)
		frame += 1
	var idle := PackedInt32Array([0, 0])
	for i in 60:
		_step_flow(flow, idle)
		music = _music_after(flow.sim.events, music)
	expect_equal(flow.state, GameFlow.State.SELECT, "on the character select")
	expect_equal(music, CharacterSelect.MUSIC_SELECT, "the select music plays")
	for pads: PackedInt32Array in [PackedInt32Array([PadState.START, 0]), PackedInt32Array([0x900, 0])]:
		_step_flow(flow, pads)
		music = _music_after(flow.sim.events, music)
	for i in 120:
		if flow.state == GameFlow.State.MENU:
			break
		_step_flow(flow, idle)
		music = _music_after(flow.sim.events, music)
	expect_equal(flow.state, GameFlow.State.MENU, "back on the main menu")
	expect_equal(music, -1, "the music stopped")


## Arcade: the VS screen after the character select loads the fighters' pictures from the disc
## (LoadOverlaySync), which stops the select music (FUN_8006B834).
func test_vs_pictures_stop_music() -> void:
	if not require(FlowTrace.path("arcade"), "run tools/research/flow_trace.py first"):
		return
	var trace := FlowTrace.load_scenario("arcade")
	var flow := imported_flow((trace.header["scenario"] as Dictionary)["seed"] as int)
	if flow == null:
		return
	var music := -1
	var selected := false
	for frame in trace.frames:
		_step_flow(flow, PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)]))
		music = _music_after(flow.sim.events, music)
		selected = selected or (flow.state == GameFlow.State.SELECT and music == CharacterSelect.MUSIC_SELECT)
		if selected and flow.state == GameFlow.State.VS and flow.sub >= 2:
			break
	expect(selected, "the select music played")
	expect_equal(flow.state, GameFlow.State.VS, "on the VS screen")
	expect_equal(music, -1, "the VS screen's loads stopped the music")


## FUN_80036854: a fight reads its stage from the disc, which stops the music, only when another
## stage is in memory; a mode start empties the cache; Tekken Ball reads its stage every time.
func test_stage_read_stops_music() -> void:
	var flow := imported_flow()
	if flow == null:
		return
	var fight := flow.fight
	var chars := PackedInt32Array([0, 1])
	var costumes := PackedInt32Array([0, 0])
	var cpu := PackedInt32Array([0, 1])
	fight.mode = 1
	fight.stage = 3
	var cases := [[-1, true, "nothing in memory"], [3, false, "the same stage"], [5, true, "another stage"]]
	for c: Array in cases:
		fight.stage_cached = c[0]
		flow.sim.events.clear()
		flow.sim.load_fighters(chars, costumes, cpu)
		expect_equal(flow.sim.events.has(SimEvents.Kind.MUSIC_STOP), c[1] as bool, c[2] as String)
		expect_equal(fight.stage_cached, 3, "%s: the stage is noted" % c[2])
	ModeStart.start(flow, 1, 0)
	expect_equal(fight.stage_cached, -1, "a mode start empties the cache")
	fight.mode = 7
	fight.stage_cached = 3
	flow.sim.events.clear()
	flow.sim.load_fighters(chars, costumes, cpu)
	expect(flow.sim.events.has(SimEvents.Kind.MUSIC_STOP), "Tekken Ball reads its stage every time")


## The track playing after a step's music requests (−1: none).
static func _music_after(events: SimEvents, music: int) -> int:
	for e in events.items:
		match e.kind:
			SimEvents.Kind.MUSIC, SimEvents.Kind.MUSIC_PREPARE, SimEvents.Kind.MUSIC_TRACK:
				music = e.a
			SimEvents.Kind.MUSIC_STOP:
				music = -1
	return music


## One frame as the harness plays it: its movies end on their first frame.
static func _step_flow(flow: GameFlow, pads: PackedInt32Array) -> void:
	flow.step(pads)
	while flow.movie_blocking:
		flow.movie_result = 1
		flow.step(pads)
	if flow.movie_started >= 0:
		flow.movie_result = 1



## `watch(flow, trace, frame) -> bool` runs after each frame that matched the trace; the run ends
## when it returns true.
func _run(scenario: String, watch := Callable()) -> void:
	if not require(FlowTrace.path(scenario), "run tools/research/flow_trace.py first"):
		return
	var trace := FlowTrace.load_scenario(scenario)
	var flow := imported_flow((trace.header["scenario"] as Dictionary)["seed"] as int)
	if flow == null:
		return
	if _enbu == null:
		_enbu = EnbuAssets.load_from(AssetCatalog.ROOT)
	flow.performance_factory = _enbu.performance
	for poke in trace.pokes():
		flow.progress.put8(poke[0] - GameProgress.BASE, poke[1])
	var refill: Variant = trace.header.get("refill")
	if refill != null and (refill as Array).size() != REFILL_RULE:
		expect(false, "%s: an older refill rule %s; re-record it with tools/research/flow_trace.py" % [scenario, refill])
		return
	var drain: Variant = trace.header.get("drain")
	if drain != null and (drain as Array).size() != DRAIN_RULE:
		expect(false, "%s: an older drain rule %s; re-record it with tools/research/flow_trace.py" % [scenario, drain])
		return
	var compare := FighterCompare.new(trace)
	for frame in trace.frames:
		var pads := PackedInt32Array([trace.pad(frame, 0), trace.pad(frame, 1)])
		flow.step(pads)
		# The harness's movies end on their first frame.
		while flow.movie_blocking:
			flow.movie_result = 1
			flow.step(pads)
		if flow.movie_started >= 0:
			flow.movie_result = 1
		if refill != null:
			_refill(flow, refill as Array)
		if drain != null:
			_drain(flow, drain as Array)
		_uninitialised_results(flow, trace, frame)
		_uninitialised_ball(flow, trace, frame)
		var lines := _differences(flow, trace, frame)
		if trace.fighter_count(frame) == FightState.RECORDS and flow.sub >= 8:
			_all_fighters(lines, flow, compare, frame)
		if not lines.is_empty():
			expect(false, "%s frame %d (state %d sub %d, game %d sub %d):\n    %s" % [scenario, frame,
				flow.state, flow.sub, trace.state(frame), trace.sub_state(frame),
				"\n    ".join(lines.slice(0, MAX_REPORTED))])
			return
		if watch.is_valid() and watch.call(flow, trace, frame) as bool:
			return


## flow_trace.refill: the player's health back to its maximum and, while the round runs, the timer
## back to a minute when they run low in a Tekken Force fight, after the frame (as the harness
## does). `rule`: the health field, the health and timer limits, the timer's refill.
static func _refill(flow: GameFlow, rule: Array) -> void:
	if flow.state != GameFlow.State.FIGHT or flow.region.mode != 8:
		return
	var below: int = rule[1]
	var f := flow.fight.fighters[0]
	if f.health > 0 and f.health < below:
		f.health = f.health_max
	if flow.fight.round_state != 1:
		return
	var timer_below: int = rule[2]
	var timer_refill: int = rule[3]
	if flow.fight.timer > 0 and flow.fight.timer < timer_below:
		flow.fight.timer = timer_refill


## flow_trace.drain: while a round runs, a CPU fighter's health down to the rule's limit, after
## the frame (as the harness does). `rule`: the health field, the CPU flag field, the limit.
static func _drain(flow: GameFlow, rule: Array) -> void:
	if flow.state != GameFlow.State.FIGHT or flow.fight.round_state != 1:
		return
	var limit: int = rule[2]
	for i in 2:
		var f := flow.fight.fighters[i]
		if f.is_cpu != 0 and f.health > limit:
			f.health = limit


## Tekken Ball and Tekken Force: all three records field by field (FighterCompare), the ball and
## the modes' state.
func _all_fighters(out: PackedStringArray, flow: GameFlow, compare: FighterCompare, frame: int) -> void:
	var fight := flow.fight
	var trace := compare.trace as FlowTrace
	if fight.mode == 7 and flow.sim.ball != null:
		_ball(out, flow.sim.ball, trace, frame)
	var banks: Array[MotionBank] = [fight.fighters[0].bank, fight.fighters[1].bank, flow.content.common]
	for i in FightState.RECORDS:
		for line in compare.differences(fight.fighters[i], frame, i, banks):
			if out.size() < MAX_REPORTED:
				out.append("fighter %d %s" % [i, line])


## The ball object's fields the game writes and the simulation keeps (the rest of the heap record
## holds older data; the drawing matrix at +0x48 copies 0x800AE3E0, which the harness leaves
## empty) and volley.ovl's state (not its drawing: packets, the court's matrix, the popups'
## screen points).
const BALL_SPANS: Array[int] = [0x00, 0x04, 0x68, 0x74, 0x78, 0x84, 0x88, 0x94, 0x98, 0xA6, 0xA8, 0xB4,
	0xB8, 0x152]
const VOLLEY_SPANS: Array[int] = [0x645C, 0x645D, 0x68E8, 0x6908, 0x6948, 0x6A68, 0x6AD8, 0x6AEC,
	0x6B40, 0x6B58]


func _ball(out: PackedStringArray, ball: TekkenBall, trace: FlowTrace, frame: int) -> void:
	var shown := 0
	for k in range(0, BALL_SPANS.size(), 2):
		for at in range(BALL_SPANS[k], BALL_SPANS[k + 1]):
			var expected := trace.pointed_value(frame, "ball", at, 1)
			if ball.b.u8(at) != expected and shown < 8:
				out.append("ball +0x%X: %02X ≠ %02X" % [at, ball.b.u8(at), expected])
				shown += 1
	for k in range(0, VOLLEY_SPANS.size(), 2):
		for a in range(VOLLEY_SPANS[k], VOLLEY_SPANS[k + 1]):
			var address := 0x800B0000 + a
			var expected := trace.ram(frame, address, 1)
			if ball.v.u8(address - TekkenBall.BASE) != expected and shown < 12:
				out.append("volley 0x%08X: %02X ≠ %02X" % [address, ball.v.u8(address - TekkenBall.BASE), expected])
				shown += 1
	for i in 8:
		for at in range(0x1C, 0x20):
			var address := TekkenBall.POPUP_SLOTS + 0x20 * i + at
			var expected := trace.ram(frame, address, 1)
			if ball.v.u8(address - TekkenBall.BASE) != expected and shown < 12:
				out.append("popup %d +0x%X: %02X ≠ %02X" % [i, at, ball.v.u8(address - TekkenBall.BASE), expected])
				shown += 1


func _differences(flow: GameFlow, trace: FlowTrace, frame: int) -> PackedStringArray:
	var out := PackedStringArray()
	if flow.state != trace.state(frame) or flow.sub != trace.sub_state(frame):
		out.append("state %d sub %d ≠ %d sub %d" % [flow.state, flow.sub, trace.state(frame), trace.sub_state(frame)])
	var ours := FightCalls.of_events(flow.sim.events)
	var theirs := FightCalls.of_list(trace.calls(frame))
	if flow.state == GameFlow.State.ENBU:
		# Bug #49 (fixed): the game repeats fighter 0's frame events while both fighters move.
		ours = _unique(ours)
		theirs = _unique(theirs)
	if ours != theirs:
		out.append("calls: %s ≠ %s" % [ours, theirs])
	_blocks(out, "progress", flow.progress, GameProgress.BASE, trace, frame)
	_blocks(out, "mode", flow.region, ModeRegion.BASE, trace, frame)
	for g: Array in GLOBALS:
		var address: int = g[1]
		var size: int = g[2]
		var expected := trace.ram(frame, address, size)
		var actual := RecordTrace.width(_global(flow, g[0] as String), size)
		if actual != expected:
			out.append("%s: %d ≠ %d" % [g[0], actual, expected])
	if flow.state == GameFlow.State.QUICK_SELECT and flow.sub >= 2:
		for at: int in QUICK_FIELDS:
			if (at == 0x70 or at == 0x11C) and flow.quick.mode() != 1:
				continue            # the handicap is VS's only
			var expected := trace.ram(frame, QuickSelect.BASE + at, 4)
			if flow.quick.ctx.u32(at) != expected:
				out.append("quick select +0x%X: %d ≠ %d" % [at, flow.quick.ctx.u32(at), expected])
	if flow.state == GameFlow.State.SELECT and trace.has_range(CharacterSelect.BASE):
		_blocks(out, "select", flow.select.ctx, CharacterSelect.BASE, trace, frame)
		_blocks(out, "cells", flow.select.cells, CharacterSelect.CELLS_BASE, trace, frame)
	if flow.state == GameFlow.State.OPTIONS and flow.sub >= 1 and trace.has_range(0x800EB2F0):
		_options(out, flow, trace, frame)
	if flow.state == GameFlow.State.FIGHT and flow.region.mode == 5 and flow.sub >= 8 \
			and trace.has_range(PracticeMode.BASE):
		_practice(out, flow, trace, frame)
	if flow.state in RESULT_STATES and trace.has_range(ResultScreens.BASE):
		_result(out, flow, trace, frame)
	if flow.state == GameFlow.State.RANKING and flow.sub >= 1 and trace.has_range(RankingScreen.TABLE_BASE):
		_ranking(out, flow, trace, frame)
	if flow.state == GameFlow.State.FIGHT and trace.has_range(0x8009892C):
		_camera(out, flow, trace, frame)
	if trace.has_fighters(frame) and flow.sub >= 8:
		for i in 2:
			var f := flow.fight.fighters[i]
			for field: Array in FIGHTER_FIELDS:
				var offset: int = field[1]
				var size: int = field[2]
				var expected := trace.fighter(frame, i, offset, size)
				var actual := RecordTrace.width(_fighter(f, field[0] as String), size)
				if actual != expected:
					out.append("fighter %d %s: %d ≠ %d" % [i, field[0], actual, expected])
	return out


## The camera director's globals kept across matches and, in the fight and the Ogre scene, the view.
func _camera(out: PackedStringArray, flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	var camera := flow.sim.camera
	var ours := {"intro counter": camera.intro_counter, "winner style": camera.winner_style}
	for g: Array in DIRECTOR_GLOBALS:
		var expected := trace.ram(frame, g[1] as int, g[2] as int)
		var actual := RecordTrace.width(ours[g[0]] as int, g[2] as int)
		if actual != expected:
			out.append("%s: %d ≠ %d" % [g[0], actual, expected])
	var b := flow.fight.backdrop
	var turn := {"backdrop angle": b.angle, "backdrop prev yaw": b.prev_yaw, "backdrop yaw": b.yaw,
		"look point x": b.point_x, "look point z": b.point_z}
	if trace.has_range(0x800A9650):
		for g: Array in BACKDROP_GLOBALS:
			var expected := trace.ram(frame, g[1] as int, g[2] as int)
			var actual := RecordTrace.width(turn[g[0]] as int, g[2] as int)
			if actual != expected:
				out.append("%s: %d ≠ %d" % [g[0], actual, expected])
	if flow.sub not in VIEW_SUBS:
		return
	var view := camera.view
	var values := {"pitch": view.pitch, "yaw": view.yaw, "x": view.x, "y": view.y, "z": view.z}
	for v: Array in VIEW_FIELDS:
		var expected := trace.ram(frame, v[1] as int, -4)
		var actual := RecordTrace.width(values[v[0]] as int, -4)
		if actual != expected:
			out.append("camera %s: %d ≠ %d" % [v[0], actual, expected])


func _options(out: PackedStringArray, flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	var o := flow.options
	# A page's own words are compared once the page has run a frame.
	var ran := _options_page == o.page
	_options_page = o.page
	var page := trace.ram(frame, 0x800EC5E8, 1)
	if o.page != page:
		out.append("options page: %d ≠ %d" % [o.page, page])
	for p in 6:
		var cursor := trace.ram(frame, 0x800EB2F0 + 0x34 * p, 4)
		var sub := trace.ram(frame, 0x800EB2F4 + 0x34 * p, 4)
		if o.cursors[p] != cursor or o.subs[p] != sub:
			out.append("options page %d: cursor %d sub %d ≠ %d, %d" % [p, o.cursors[p], o.subs[p], cursor, sub])
	var card := trace.ram(frame, 0x800EC63C, 1)
	if o.page == OptionsScreen.PAGE_CARD and ran and o.card_state != card:
		out.append("card state: %d ≠ %d" % [o.card_state, card])
	if o.page == OptionsScreen.PAGE_KEYS and ran:
		for p in 2:
			var at := 0x800EC640 + 0x1E8 * p
			var rec := o.keys[p]
			var names := ["selected", "armed", "busy", "used"]
			var values := PackedInt32Array([rec.selected, rec.armed, rec.busy, rec.used])
			var offsets := PackedInt32Array([4, 8, 0xC, 0x24])
			for k in names.size():
				var expected := trace.ram(frame, at + offsets[k], 4)
				if values[k] != expected:
					out.append("key config %d %s: %d ≠ %d" % [p, names[k], values[k], expected])
	if o.page == OptionsScreen.PAGE_RECORDS and o.subs[OptionsScreen.PAGE_RECORDS] != 0:
		var sub := trace.ram(frame, 0x800ECA10, 4)
		if o.record_page != sub:
			out.append("records page: %d ≠ %d" % [o.record_page, sub])
		for i in 4:
			var top := trace.ram(frame, 0x800ECA20 + 0x20 * i, 4)
			var count := trace.ram(frame, 0x800ECA24 + 0x20 * i, 4)
			if o.record_tops[i] != top or o.record_lists[i].size() != count:
				out.append("records list %d: top %d count %d ≠ %d, %d" % [i, o.record_tops[i], o.record_lists[i].size(), top, count])
			for k in mini(count, 22):
				var id := trace.ram(frame, 0x800ECA28 + 0x20 * i + k, 1)
				if k < o.record_lists[i].size() and o.record_lists[i][k] != id:
					out.append("records list %d row %d: %d ≠ %d" % [i, k, o.record_lists[i][k], id])
					break


## Practice S compared: the menu, the per-player attack data, the key ring and the replay (the
## menu's row colours and the markers' screen points belong to the drawing).
const PRACTICE_SPANS: Array[int] = [0x00, 0x54, 0x74, 0x8C, 0x9D, 0xAD, 0xB0, 0x1F8]   ## start, end pairs


func _practice(out: PackedStringArray, flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	var s := flow.practice.s
	var theirs := trace.block(frame, PracticeMode.BASE, PracticeMode.SIZE)
	var shown := 0
	for k2 in range(0, PRACTICE_SPANS.size(), 2):
		for i in range(PRACTICE_SPANS[k2], PRACTICE_SPANS[k2 + 1]):
			if s.bytes[i] != theirs[i] and shown < 8:
				out.append("practice S+0x%X: %02X ≠ %02X" % [i, s.bytes[i], theirs[i]])
				shown += 1
	for i in 4:
		var at := PracticeMode.MARKERS + 8 * i
		for k in 4:
			if s.bytes[at + k] != theirs[at + k] and shown < 8:
				out.append("practice marker %d +%d: %02X ≠ %02X" % [i, k, s.bytes[at + k], theirs[at + k]])
				shown += 1
	var paused := trace.ram(frame, 0x800958DC, 4)
	if flow.fight.practice_paused != paused:
		out.append("practice paused: %d ≠ %d" % [flow.fight.practice_paused, paused])
	var intro := trace.ram(frame, 0x800958E0, 4)
	if flow.fight.practice_intro != intro:
		out.append("practice intro: %d ≠ %d" % [flow.fight.practice_intro, intro])


## result.ovl's state and banner lie past the overlay's image and are never cleared: the game
## starts from whatever the memory held (the banner's scroll, fields written later). On the frame
## a result state is entered the remake's blocks take the trace's bytes.
func _uninitialised_results(flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	if flow.sub != 0 or flow.state < GameFlow.State.TEAM_RESULT or flow.state > GameFlow.State.SURVIVAL_RESULT:
		return
	for at in range(0, ResultScreens.SIZE, 4):
		flow.results.state.put32(at, trace.ram(frame, ResultScreens.BASE + at, 4))
	for at in range(0, 8, 4):
		flow.results.banner.put32(at, trace.ram(frame, ResultScreens.BANNER_BASE + at, 4))


## Tekken Ball's ball object is allocated in the fight heap (FightPrepare), whose memory holds
## older data: the fields the game never writes keep it. The remake's object takes the trace's
## bytes on the frame it is made.
var _seeded_ball: TekkenBall


func _uninitialised_ball(flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	var ball := flow.fight.ball
	if ball == null or ball == _seeded_ball or not trace.has_pointed("ball"):
		return
	_seeded_ball = ball
	for at in TekkenBall.BALL_SIZE:
		ball.b.put8(at, trace.pointed_value(frame, "ball", at, 1))


func _result(out: PackedStringArray, flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	# On the frame the state is entered the handler has not run: result.ovl's image still holds
	# its file bytes where the remake's state is zero.
	if flow.sub == 0:
		return
	var r := flow.results
	var fields: Array = RESULT_FIELDS[flow.state]
	for at: int in fields:
		var expected := trace.ram(frame, ResultScreens.BASE + at, 4)
		if r.state.u32(at) != expected:
			out.append("result +0x%X: %d ≠ %d" % [at, r.state.u32(at), expected])
	var seq := trace.ram(frame, 0x800A37A8, 1)
	if r.seq_state != seq:
		out.append("voice sequence: %d ≠ %d" % [r.seq_state, seq])
	if flow.state != GameFlow.State.TIME_RESULT:
		_blocks(out, "banner", r.banner, ResultScreens.BANNER_BASE, trace, frame)


func _ranking(out: PackedStringArray, flow: GameFlow, trace: FlowTrace, frame: int) -> void:
	var table := flow.ranking.table
	for f: Array in RANKING_FIELDS:
		var at: int = f[1]
		var size: int = f[2]
		var after: int = f[3]
		if flow.sub < after or (at == 0x86 and flow.sub > 0xD):
			continue
		var expected := trace.ram(frame, RankingScreen.TABLE_BASE + at, size)
		var actual := table.u16(at) if size == 2 else table.u32(at)
		if actual != expected:
			out.append("ranking %s: %d ≠ %d" % [f[0], actual, expected])
	for i in mini(table.u16(0xC), 22):
		var expected := trace.ram(frame, RankingScreen.TABLE_BASE + 0xE + 2 * i, 2)
		if table.u16(0xE + 2 * i) != expected:
			out.append("ranking row %d: %d ≠ %d" % [i, table.u16(0xE + 2 * i), expected])
	if flow.sub == 0xC or flow.sub == 0xD:
		_blocks(out, "name", flow.ranking.name, RankingScreen.NAME_BASE, trace, frame)
	var camera := flow.ranking.backdrop
	for at: int in [4, 0x14, 0x18, 0x1C]:
		var expected := trace.ram(frame, RankingScreen.BACKDROP_BASE + at, 4)
		if camera.u32(at) != expected:
			out.append("ranking camera +0x%X: %d ≠ %d" % [at, camera.u32(at), expected])


static func _unique(calls: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for c in calls:
		if c not in out:
			out.append(c)
	return out


func _blocks(out: PackedStringArray, name: String, ours: ByteBlock, base: int, trace: FlowTrace, frame: int) -> void:
	var theirs := trace.block(frame, base, ours.bytes.size())
	if theirs == ours.bytes:
		return
	var shown := 0
	for i in ours.bytes.size():
		if ours.bytes[i] != theirs[i]:
			out.append("%s 0x%08X: %02X ≠ %02X" % [name, base + i, ours.bytes[i], theirs[i]])
			shown += 1
			if shown >= 8:
				return


func _global(flow: GameFlow, name: String) -> int:
	var gl := flow.globals
	var fight := flow.fight
	match name:
		"char 0": return gl.player_char[0]
		"char 1": return gl.player_char[1]
		"costume 0": return gl.player_costume[0]
		"costume 1": return gl.player_costume[1]
		"cpu 0": return gl.player_cpu[0]
		"cpu 1": return gl.player_cpu[1]
		"active 0": return gl.player_active[0]
		"active 1": return gl.player_active[1]
		"keep 0": return gl.player_keep[0]
		"keep 1": return gl.player_keep[1]
		"other player": return gl.other_player
		"win streak": return gl.win_streak
		"tie choice": return fight.tie_choice
		"save pending": return gl.save_pending
		"challenger lock": return fight.challenger_lock
		"state timer": return flow.sim.state_timer
		"stage": return fight.stage
		"music": return fight.music
		"round time": return fight.round_time_option
		"human mask": return fight.human_mask
		"difficulty": return fight.ai_difficulty
		"level": return fight.ai_level
		"attract": return fight.attract
		"hud shown": return fight.hud_shown
		"rand": return fight.rng.state
		"frame rng": return fight.frame_rng
		"camera rng": return fight.camera_rng
		"pad repeat 0": return flow.sim.pads.repeat[0]
		"pad repeat 1": return flow.sim.pads.repeat[1]
	return 0


func _fighter(f: FighterState, name: String) -> int:
	match name:
		"charId": return f.char_id
		"costume key": return f.costume_key
		"isCpu": return f.is_cpu
		"health": return f.health
		"roundWins": return f.round_wins
		"posX": return f.pos_x
		"posZ": return f.pos_z
		"poseFrame": return f.pose_frame
	return 0
