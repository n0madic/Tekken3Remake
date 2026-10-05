extends TestSuite
## Theater's sound page (TheaterScreen) in a build without movies: THEATER (the way to the movies)
## is not offered, but BGM SELECT and EXIT stay reachable.


func _press(flow: GameFlow, pad: int) -> void:
	flow.sim.pads.repeat[0] = pad
	flow.sim.pads.repeat[1] = 0
	flow.sim.pads.physical_pressed[0] = 0
	flow.sim.pads.physical_pressed[1] = 0
	flow.theater._sound_input()


func _flow(movies: bool) -> GameFlow:
	var flow := imported_flow()
	if flow == null:
		return null
	flow.movies_available = movies
	flow.theater.kind = TheaterScreen.PAGE_ARRANGE
	flow.theater.reset()
	return flow


func test_buttons_are_reachable_without_movies() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _flow(false)
	var t := flow.theater
	_press(flow, PadState.RIGHT)
	expect_equal(t.focus, TheaterScreen.Focus.BGM, "right from the list: BGM SELECT")
	_press(flow, PadState.DOWN)
	expect_equal(t.focus, TheaterScreen.Focus.EXIT, "down: EXIT")
	_press(flow, PadState.UP)
	expect_equal(t.focus, TheaterScreen.Focus.BGM, "up: BGM SELECT")
	_press(flow, PadState.UP)
	expect_equal(t.focus, TheaterScreen.Focus.BGM, "THEATER is not offered above it")
	_press(flow, PadState.LEFT)
	expect_equal(t.focus, TheaterScreen.Focus.LIST, "left: the list")


func test_theater_button_with_movies() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _flow(true)
	var t := flow.theater
	_press(flow, PadState.RIGHT)
	expect_equal(t.focus, TheaterScreen.Focus.SWITCH, "right from the list: THEATER")
	_press(flow, PadState.DOWN)
	expect_equal(t.focus, TheaterScreen.Focus.BGM, "down: BGM SELECT")
	_press(flow, PadState.UP)
	expect_equal(t.focus, TheaterScreen.Focus.SWITCH, "up: THEATER again")
