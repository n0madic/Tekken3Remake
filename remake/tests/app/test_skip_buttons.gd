extends TestSuite
## SkipButtons: ✕ and ○ act as Start on what the game skips with Start, and nowhere else.


func _flow() -> GameFlow:
	return imported_flow()


func _mapped(flow: GameFlow, pad: int, movie := false) -> int:
	return SkipButtons.apply(PackedInt32Array([pad, 0]), flow, movie)[0]


func test_cross_and_circle_skip_the_attract_sequence() -> void:
	var flow := _flow()
	if flow == null:
		return
	for state: GameFlow.State in [GameFlow.State.TITLE, GameFlow.State.ENBU]:
		flow.state = state
		expect_equal(_mapped(flow, PadState.CROSS), PadState.CROSS | PadState.START, "✕ in state %d" % state)
		expect_equal(_mapped(flow, PadState.CIRCLE), PadState.CIRCLE | PadState.START, "○ in state %d" % state)
		expect_equal(_mapped(flow, PadState.SQUARE), PadState.SQUARE, "□ in state %d" % state)
	flow.state = GameFlow.State.TRANSITION
	flow.progress.transition_target = GameFlow.State.ENBU
	expect_equal(_mapped(flow, PadState.CROSS), PadState.CROSS | PadState.START, "✕ on the way to the demonstration")
	flow.progress.transition_target = GameFlow.State.MENU
	expect_equal(_mapped(flow, PadState.CROSS), PadState.CROSS, "✕ on the way to the menu")


func test_fights_skip_only_replays_and_the_demonstration() -> void:
	var flow := _flow()
	if flow == null:
		return
	flow.state = GameFlow.State.FIGHT
	flow.region.mode = 0
	flow.fight.replay_playing = 0
	expect_equal(_mapped(flow, PadState.CROSS), PadState.CROSS, "✕ in a fight is a punch")
	flow.fight.replay_playing = 1
	expect_equal(_mapped(flow, PadState.CROSS), PadState.CROSS | PadState.START, "✕ skips a replay")
	flow.fight.replay_playing = 0
	flow.region.mode = 6
	expect_equal(_mapped(flow, PadState.CIRCLE), PadState.CIRCLE | PadState.START, "○ skips the demonstration fight")


func test_menus_keep_their_buttons_but_movies_skip() -> void:
	var flow := _flow()
	if flow == null:
		return
	flow.state = GameFlow.State.MENU
	expect_equal(_mapped(flow, PadState.CROSS), PadState.CROSS, "✕ in the menu")
	expect_equal(_mapped(flow, PadState.CROSS, true), PadState.CROSS | PadState.START, "✕ during a movie")
	var both := SkipButtons.apply(PackedInt32Array([PadState.CROSS, PadState.CIRCLE]), flow, true)
	expect_equal(both, PackedInt32Array([PadState.CROSS | PadState.START, PadState.CIRCLE | PadState.START]), "both pads")
