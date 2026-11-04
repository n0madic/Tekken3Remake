extends TestSuite
## The drawing rules the Tekken Force and Tekken Ball views take from the game: the items' boxes,
## the GPU's coordinate limits (the ball's streaks), and the one-sided panorama seen from the
## cameras that orbit inside it.

const FIGHT_STAGES := 15               ## FightContent.STAGE_LETTERS: stages 0–14


## FUN_800B4374's box: 0x15E00 / (SZ >> 2) wide, 0x2BC00 / (SZ >> 2) high, centred on the point's x,
## its bottom a height above the point (SZ 7964: 45 × 90, the size of the items in the Force
## traces' packets).
func test_item_box_follows_the_game_formula() -> void:
	var box := ForceItemsView.picture_box(PackedInt32Array([473, 524, 7964]))
	expect_equal(box, PackedFloat32Array([451, 344, 45, 90, 7964]), "picture box")


func test_item_box_survives_a_point_at_the_eye() -> void:
	var box := ForceItemsView.picture_box(PackedInt32Array([100, 100, 0]))
	expect_equal(box[2], float(ForceItemsView.WIDTH), "a depth of 0 counts as 1")


func test_gpu_coordinates_wrap_at_11_bits() -> void:
	expect_equal(ScreenCanvas.gpu_coordinate(1023), 1023, "the largest")
	expect_equal(ScreenCanvas.gpu_coordinate(1024), -1024, "past it wraps")
	expect_equal(ScreenCanvas.gpu_coordinate(-1), -1, "negative")
	expect_equal(ScreenCanvas.gpu_coordinate(0x10005), 5, "upper bits dropped")


func test_gpu_skips_oversized_polygons() -> void:
	var fits: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1023, 480), Vector2i(-0, 511)]
	expect(ScreenCanvas.gpu_draws(fits), "1023 × 511 is drawn")
	var wide: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1023, 0), Vector2i(0, 10)]
	expect(not ScreenCanvas.gpu_draws(wide), "1024 wide is skipped")
	var tall: Array[Vector2i] = [Vector2i(0, -40), Vector2i(8, 480), Vector2i(0, 480)]
	expect(not ScreenCanvas.gpu_draws(tall), "520 tall is skipped")


## The panorama is culled from outside (panorama.gdshader): the ranking's orbiting camera and
## the rig's coverage eye stay inside every fight stage's panorama.
func test_backdrop_cameras_stay_inside_the_panorama() -> void:
	if not require(AssetCatalog.ROOT.path_join("stages/a/stage.json")):
		return
	for letter in FightContent.STAGE_LETTERS.substr(0, FIGHT_STAGES):
		var stage := StageData.load_from(AssetCatalog.ROOT.path_join("stages/" + letter))
		var e := stage.panorama_extent
		var k := StageView.PANORAMA_PARALLAX
		var box := Rect2(e[0] * k, e[2] * k, (e[1] - e[0]) * k, (e[3] - e[2]) * k)
		var orbit := RankingScreen.ORBIT_RADIUS
		expect(box.has_point(Vector2(-orbit, -orbit)) and box.has_point(Vector2(orbit, orbit)),
			"stage %s: the ranking orbit inside %s" % [letter, box])
		expect(box.has_point(Vector2(stage.coverage_eye[0], stage.coverage_eye[2])),
			"stage %s: the coverage eye inside %s" % [letter, box])


## FUN_8004EFF8's choice per mode (the Python port's _arcade_code, _team_code, _ta_code, _surv_code,
## _ball_code): one human on pad 0 unless a case says otherwise.
func test_mode_line_codes() -> void:
	var cases := [
		# mode, humans, active pad 0, pad 1, continuing, lock, challenger, expected pad 0, pad 1
		[GameMode.ARCADE, 1, 1, 0, 0, 0, 0, ModeLine.STAGE_TIME, ModeLine.COIN],
		[GameMode.ARCADE, 1, 1, 0, 1, 0, 0, ModeLine.STAGE_TIME, ModeLine.GAME_OVER],
		[GameMode.ARCADE, 1, 1, 0, 0, 1, 0, ModeLine.STAGE_TIME, ModeLine.GAME_OVER],
		[GameMode.ARCADE, 1, 1, 0, 0, 0, 1, ModeLine.STAGE_TIME, ModeLine.NONE],
		[GameMode.TEAM, 1, 1, 0, 0, 0, 0, ModeLine.TEAM, ModeLine.COIN],
		[GameMode.TEAM, 2, 1, 1, 0, 0, 0, ModeLine.TEAM, ModeLine.NONE],
		[GameMode.TIME_ATTACK, 1, 1, 0, 0, 0, 0, ModeLine.STAGE_TIME, ModeLine.TIME_ATTACK],
		[GameMode.SURVIVAL, 1, 1, 0, 0, 0, 0, ModeLine.SURVIVAL_COUNT, ModeLine.SURVIVAL],
		[GameMode.SURVIVAL, 1, 0, 0, 0, 0, 0, ModeLine.GAME_OVER, ModeLine.SURVIVAL],
		[GameMode.DEMO, 0, 0, 0, 0, 0, 0, ModeLine.COIN, ModeLine.COIN],
		[GameMode.BALL, 1, 1, 0, 0, 0, 0, ModeLine.BALL, ModeLine.COIN],
		[GameMode.FORCE, 1, 1, 0, 0, 0, 0, ModeLine.SCORE, ModeLine.SCORE],
		[GameMode.VS, 2, 1, 1, 0, 0, 0, ModeLine.NONE, ModeLine.NONE],
		[GameMode.PRACTICE, 1, 1, 0, 0, 0, 0, ModeLine.NONE, ModeLine.NONE],
	]
	for c: Array in cases:
		var fight := FightState.new(null, RuleSet.original())
		fight.region.mode = c[0]
		fight.region.human_count = c[1]
		fight.region.continuing = c[4]
		fight.challenger_lock = c[5]
		fight.region.challenger = c[6]
		var humans := PackedInt32Array([c[2], c[3]])
		expect_equal(ModeLine.code(fight, humans, 0), c[7], "mode %d, pad 0: %s" % [c[0], str(c)])
		expect_equal(ModeLine.code(fight, humans, 1), c[8], "mode %d, pad 1: %s" % [c[0], str(c)])


## Two humans in arcade: GAME OVER blinks on the loser's side of a decided match.
func test_mode_line_two_player_arcade() -> void:
	var fight := FightState.new(null, RuleSet.original())
	fight.region.mode = GameMode.ARCADE
	fight.region.human_count = 2
	fight.region.match_result = 1
	fight.region.match_loser = 1
	fight.vblank = 0x18
	var humans := PackedInt32Array([1, 1])
	expect_equal(ModeLine.code(fight, humans, 1), ModeLine.GAME_OVER, "the loser, blink on")
	expect_equal(ModeLine.code(fight, humans, 0), ModeLine.NONE, "the winner")
	fight.vblank = 0x20
	expect_equal(ModeLine.code(fight, humans, 1), ModeLine.NONE, "the loser, blink off")


## Records TeamIconsView's sprites in drawing order instead of drawing them.
class IconRecorder extends TeamIconsView:
	var calls: Array = []

	func image(_tex: Texture2D, x: float, _y: float, _w: float = -1.0, _h: float = -1.0,
			_modulate_colour := Color.WHITE, flip := false) -> void:
		calls.append(["icon", int(x), flip])

	func sprt(x: float, _y: float, _w: int, _h: int, _uv_clut: int, _tpage: int, _tint := Color.WHITE) -> void:
		calls.append(["cross", int(x)])


## Records the CLUTs of the sprites asked for.
class ClutRecorder extends VramImage:
	var cluts: Array = []

	func sprite(_u: int, _v: int, _w: int, _h: int, clut: int, _tpage: int) -> Texture2D:
		cluts.append(clut)
		return null


func _team_view(side: int, count: int, lost: int, result: int, vblank: int) -> IconRecorder:
	var fight := FightState.new(null, RuleSet.original())
	var team := ModeRegion.CONTEXT + ModeRules.TEAMS + ModeRules.TEAM_SIZE * side
	fight.region.put8(team + TeamIconsView.TEAM_COUNT, count)
	fight.region.put8(team + TeamIconsView.TEAM_CURRENT, lost)
	fight.region.match_result = result
	fight.vblank = vblank
	var view := IconRecorder.new()
	view.vram = ClutRecorder.new()
	view._fight = fight
	view._side(side)
	return view


## FUN_800B1C2C (`hud_team`): the last member is drawn first, each cross over its icon, and player
## 2's icons are mirrored; the member a decided match has beaten is crossed out and blinks.
func test_team_icons() -> void:
	var view := _team_view(0, 3, 1, 2, 0x10)
	expect_equal(view.calls, [["icon", 0x8A, false], ["icon", 0x93, false], ["cross", 0x93],
		["icon", 0x9C, false], ["cross", 0x9C]], "player 1: the first lost, the second beaten")
	expect_equal((view.vram as ClutRecorder).cluts, [TeamIconsView.CLUT_LEFT, TeamIconsView.CLUT_LEFT,
		TeamIconsView.CLUT_GONE], "the beaten member lit while the blink is on")
	view.free()
	view = _team_view(0, 3, 1, 2, 0)
	expect_equal((view.vram as ClutRecorder).cluts[1], TeamIconsView.CLUT_GONE, "and dark while it is off")
	view.free()
	view = _team_view(1, 2, 0, 0, 0)
	expect_equal(view.calls, [["icon", 0xD3, true], ["icon", 0xCA, true]], "player 2, undecided")
	view.free()
	view = _team_view(1, 2, 0, 2, 0)
	expect_equal(view.calls, [["icon", 0xD3, true], ["icon", 0xCA, true]], "player 1 won: player 2 lost no blink")
	view.free()
	view = _team_view(1, 2, 0, 1, 0)
	expect_equal(view.calls.size(), 3, "player 2 won: its next member is marked")
	view.free()


## Records the mode line's texts instead of drawing them.
class LineRecorder extends ModeHudView:
	var calls: Array = []

	func ptext(format_address: int, args: Array) -> void:
		calls.append([format_address, args])

	func print_fmt(_fmt: String, args: Array, _font_index := 0, _colour := 0) -> void:
		calls.append(args)


## Answers a table's entries with their addresses.
class AddressRam extends GameRam:
	func u32(address: int) -> int:
		return address

	func string(_address: int) -> String:
		return ""


## FUN_800B1E78: STAGE n, the last stage's FINAL blinking, and the time capped at 99'59"98.
func test_stage_time() -> void:
	var fight := FightState.new(null, RuleSet.original())
	fight.region.fight_index = 8
	fight.region.fight_clock = 3661
	fight.region.total_time = 100
	var view := LineRecorder.new()
	view._stage_time(fight, 10, 24)
	expect_equal(view.calls[0], [ModeHudView.STR_STAGE, [7, 0, 10, 24, 9]], "stage 9")
	expect_equal(view.calls[2], [ModeHudView.STR_TIME, [5, 0, 85, 24, 1, 109, 2, 135, 68]], "the run's time: 3761 frames")
	view.calls.clear()
	fight.region.fight_index = 9
	fight.region.total_time = ModeHudView.TIME_CAP
	fight.vblank = 0
	view._stage_time(fight, 10, 24)
	expect_equal(view.calls[0], [ModeHudView.STR_FINAL_STAGE, [7, 0, 10, 24, 10]], "the last stage")
	expect_equal(view.calls[2], [ModeHudView.STR_TIME, [5, 0, 85, 24, 99, 109, 59, 135, 98]], "the cap")
	view.calls.clear()
	fight.vblank = 0x20
	view._stage_time(fight, 10, 24)
	expect_equal(view.calls[0][0], ModeHudView.STR_STAGE, "the blink's other phase")
	view.free()


## FUN_800B20DC and FUN_800B2004: the rank's title (none at 0, the last from 10) and the wins'
## format by their digits, at most 9999.
func test_survival_line() -> void:
	var view := LineRecorder.new()
	view.ram = AddressRam.new()
	view._survival_count(0, 10, 24)
	expect_equal(view.calls, [], "no title at rank 0")
	view._survival_count(15, 10, 24)
	expect_equal(view.calls, [[5, 0, 10, 24]], "a title")
	for c: Array in [[1, 1], [9, 9], [1000, 1000], [12000, 9999]]:
		view.calls.clear()
		view._survival_wins(c[0] as int, 58, 24)
		expect_equal(view.calls, [[1, 0, 58, 24, c[1]]], "%d wins" % [c[0]])
	view.free()
