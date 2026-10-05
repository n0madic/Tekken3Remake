extends TestSuite
## The main menu (MainMenu): TEKKEN BALL and TEKKEN FORCE start their modes.



func test_ball_and_force_start() -> void:
	for mode: int in [MainMenu.MODE_BALL, MainMenu.MODE_FORCE]:
		var flow := imported_flow()
		if flow == null:
			return
		flow.state = GameFlow.State.MENU
		flow.sub = 0
		flow.progress.ball_new = 1
		var idle := PackedInt32Array([0, 0])
		flow.step(idle)
		var shown := -1
		for i in flow.menu.entries.size():
			if flow.menu.entries[i].entry.mode == mode:
				shown = i
		expect(shown >= 0, "mode %d is listed" % mode)
		flow.progress.menu_cursor = shown
		flow.step(PackedInt32Array([PadState.START, 0]))
		flow.step(idle)
		expect_equal(flow.state, GameFlow.State.PREPARE, "mode %d starts" % mode)
		expect_equal(flow.region.mode, mode, "mode %d" % mode)
		if mode == MainMenu.MODE_BALL:
			expect_equal(flow.progress.ball_new, 2, "choosing Tekken Ball counts towards its NEW mark")
