extends TestSuite
## The pause menu (PauseMenu, FUN_8007854C): Start pauses a running round, CANCEL resumes it at
## the next pause check, RESET and Start + Select leave the fight.


var _content: FightContent


func _sim() -> FightSimulation:
	if _content == null:
		_content = FightContent.load_from(AssetCatalog.ROOT)
	var setup := FightSetup.new()
	var sim := FightSimulation.new(_content, setup, RuleSet.original())
	for i in 400:
		sim.step(PackedInt32Array([0, 0]))
		if sim.fight.round_state == 1 and sim.fight.round_frame > 10:
			break
	return sim


func _press(sim: FightSimulation, pad0: int) -> void:
	sim.step(PackedInt32Array([pad0, 0]))
	sim.step(PackedInt32Array([0, 0]))


func _paused(sim: FightSimulation) -> bool:
	return sim.fight.paused_player != 0


func test_cancel_resumes() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _sim()
	expect_equal(sim.fight.round_state, 1, "the round runs")
	_press(sim, PadState.START)
	expect(_paused(sim), "Start pauses")
	var frame := sim.fight.round_frame
	for i in 4:
		sim.step(PackedInt32Array([0, 0]))
	expect_equal(sim.fight.round_frame, frame, "the fight stands still while paused")
	_press(sim, PadState.CROSS)
	sim.step(PackedInt32Array([0, 0]))
	expect(not _paused(sim), "CANCEL resumes")
	expect(not sim.exit_requested, "CANCEL does not leave")


func test_reset_leaves() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _sim()
	_press(sim, PadState.START)
	for i in 3:
		sim.step(PackedInt32Array([0, 0]))
	_press(sim, PadState.DOWN)
	_press(sim, PadState.DOWN)
	expect_equal(sim.fight.pause_cursor, 2, "RESET is chosen")
	_press(sim, PadState.CROSS)
	sim.step(PackedInt32Array([0, 0]))
	expect(sim.exit_requested, "RESET leaves the fight")


func test_start_select_leaves() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _sim()
	sim.step(PackedInt32Array([PadState.START, 0]))
	sim.step(PackedInt32Array([PadState.START | PadState.SELECT, 0]))
	expect(sim.exit_requested, "Select pressed while Start is held leaves")


## FUN_8007854C draws nothing while the menu is inert: the two frames after it opens.
func test_menu_shows_after_two_inert_frames() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _sim()
	var shown: Array[bool] = []
	sim.step(PackedInt32Array([PadState.START, 0]))
	shown.append(sim.events.has(SimEvents.Kind.PAUSE_MENU))
	for i in 2:
		sim.step(PackedInt32Array([0, 0]))
		shown.append(sim.events.has(SimEvents.Kind.PAUSE_MENU))
	expect_equal(shown, [false, false, true] as Array[bool], "menu drawn from the third paused frame")


## COMMAND shows every human side's move list (MoveListScreen), scrolled by its own pad; a button
## returns to the menu with the cursor on CANCEL.
func test_command_page_scrolls_and_returns() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _sim()
	_press(sim, PadState.START)
	for i in 3:
		sim.step(PackedInt32Array([0, 0]))
	_press(sim, PadState.DOWN)
	_press(sim, PadState.CROSS)
	expect_equal(sim.fight.pause_page, PauseMenu.PAGE_COMMAND, "COMMAND chosen")
	for i in 3:
		sim.step(PackedInt32Array([0, 0]))
	var shown := sim.events.first(SimEvents.Kind.MOVE_LIST)
	expect(shown != null, "the lists are shown")
	if shown != null:
		expect_equal(shown.a, sim.fight.human_mask, "every human side's list")
	expect(MoveListScreen.count(sim.fight.fighters[0]) > 0, "the costume has a move list")
	sim.step(PackedInt32Array([PadState.DOWN, 0]))
	expect_equal(sim.fight.command_cursor[0], 1, "down moves player 1's list")
	expect_equal(sim.fight.command_cursor[1], 0, "player 2's list stays")
	var offsets: Array[int] = [sim.fight.command_offset[0]]
	sim.step(PackedInt32Array([0, 0]))
	offsets.append(sim.fight.command_offset[0])
	expect_equal(offsets, [42, 27] as Array[int], "the slide keeps two thirds each frame")
	_press(sim, PadState.CROSS)
	expect_equal(sim.fight.pause_page, 0, "a button returns to the menu")
	expect_equal(sim.fight.pause_cursor, 0, "on CANCEL")
	expect(_paused(sim), "still paused")


## The remake's Escape on the menu resumes as CANCEL does.
func test_escape_cancels() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var sim := _sim()
	sim.step(PackedInt32Array([PadState.START, 0]))
	expect(not PauseMenu.escape(sim.fight, sim.events), "not while the menu is inert")
	for i in 3:
		sim.step(PackedInt32Array([0, 0]))
	_press(sim, PadState.DOWN)
	expect(PauseMenu.escape(sim.fight, sim.events), "the menu takes it")
	sim.step(PackedInt32Array([0, 0]))
	expect(not _paused(sim), "resumed")
	expect(not sim.exit_requested, "without leaving")
