extends TestSuite
## A movie played inside a frame (GameFlow.start_blocking_movie): the frames wait for it, and the
## frame that finishes after it does not ask for the movie again.


func test_finished_movie_is_not_started_again() -> void:
	var flow := _ending_flow()
	if flow == null:
		return
	var pads := PackedInt32Array([0, 0])
	flow.step(pads)
	expect(flow.movie_blocking, "the ending movie holds the frames")
	expect_equal(flow.movie_started, 1, "and is asked for")
	flow.step(pads)
	expect(flow.movie_blocking, "still playing")
	flow.movie_result = 1
	flow.step(pads)
	expect(not flow.movie_blocking, "the movie has ended")
	expect_equal(flow.movie_started, -1, "the frame that finishes does not ask for it again")
	expect_equal(flow.sub, 3, "the staff roll starts")


## The frames as the app plays them: the step in which Start first shows is read by the flow, the
## skip is decided from that read (SkipButtons), and the movie's end comes before the next step,
## which finishes the frame. Start, still held after the movie, is no new press for the staff roll.
func test_skip_press_is_not_pressed_again_after_the_movie() -> void:
	var flow := _ending_flow()
	if flow == null:
		return
	var none := PackedInt32Array([0, 0])
	var start := PackedInt32Array([0, PadState.START])
	flow.step(none)
	expect(flow.movie_blocking, "the ending movie holds the frames")
	flow.step(none)
	expect(not SkipButtons.skips_blocking_movie(flow), "no button: the movie plays on")
	flow.step(start)
	expect(SkipButtons.skips_blocking_movie(flow), "player 2's Start skips the movie")
	flow.movie_result = 1                  # MoviePlayer.stop() → game.gd _on_movie_finished
	flow.step(start)
	expect(not flow.movie_blocking, "the movie has ended")
	flow.step(start)
	expect_equal(flow.sim.pads.physical[1], PadState.START, "Start is held")
	expect_equal(flow.sim.pads.physical_pressed[1], 0, "but is no new press after the movie")


## ✕ held from the Theater's choice, then still held while the movie starts: no skip.
func test_held_choice_button_does_not_skip() -> void:
	var flow := _ending_flow()
	if flow == null:
		return
	var cross := PackedInt32Array([PadState.CROSS, 0])
	flow.step(cross)
	flow.step(SkipButtons.apply(cross, flow, true))
	flow.step(SkipButtons.apply(cross, flow, true))
	expect(flow.movie_blocking, "the movie plays")
	expect(not SkipButtons.skips_blocking_movie(flow), "the held ✕ is no press")
	var released := PackedInt32Array([0, 0])
	flow.step(released)
	flow.step(cross)
	expect(SkipButtons.skips_blocking_movie(flow), "pressed again, ✕ skips")


func _ending_flow() -> GameFlow:
	var flow := imported_flow()
	if flow == null:
		return null
	flow.state = GameFlow.State.ENDING
	flow.sub = 2
	flow.theater.kind = 0
	flow.theater.movie = 1
	return flow
