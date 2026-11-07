extends TestSuite
## The round-end replay shows the arcade models' hands as the match did (issue
## n0madic/Tekken3Remake#23). The game's replay frame holds only the coarse `hands` variants of the
## PlayStation's models; the arcade models' hands (and True Ogre's tail) are selected by the channels'
## values, which the replay's start rests at the costume's shape, so they stayed open. The remake
## records the values with each frame (ReplayState.hand_levels) and FighterHands.shown returns them.


func _fighter(index: int) -> FighterState:
	var f := FighterState.new()
	f.index = index
	f.player_index = mini(index, 1)
	return f


func test_the_recorded_values_come_back_in_the_replay() -> void:
	var replay := ReplayState.new()
	var f := _fighter(0)
	replay.mode = ReplayState.RECORDING
	for n in 3:
		replay.record = n
		f.hands.current = PackedInt32Array([0x40 * n, 0x201 + n])
		expect(replay.hand_levels(f).is_empty(), "recording: the live values are drawn")
	f.hands.current = PackedInt32Array([0, 0])           # hands_rest at the replay's start
	for mode: int in [ReplayState.FIRST_FRAME, ReplayState.PLAYING]:
		replay.mode = mode
		for n in 3:
			replay.play = 2 * n                          # the playback runs in half frames
			expect_equal(replay.hand_levels(f), PackedInt32Array([0x40 * n, 0x201 + n]), "mode %d, frame %d" % [mode, n])


func test_a_recorded_frame_is_a_copy() -> void:
	var replay := ReplayState.new()
	var f := _fighter(0)
	replay.mode = ReplayState.RECORDING
	replay.record = 5
	f.hands.current = PackedInt32Array([0x200, 0x200])
	replay.hand_levels(f)
	f.hands.current[0] = 0                               # the live hand opens afterwards
	replay.mode = ReplayState.PLAYING
	replay.play = 10
	expect_equal(replay.hand_levels(f), PackedInt32Array([0x200, 0x200]), "the fist stays recorded")


func test_nothing_is_returned_outside_the_replay() -> void:
	var replay := ReplayState.new()
	var f := _fighter(0)
	f.hands.current = PackedInt32Array([0x200, 0x200])
	for mode: int in [ReplayState.STARTING, ReplayState.ENDING, ReplayState.DONE, 0]:
		replay.mode = mode
		expect(replay.hand_levels(f).is_empty(), "mode %d: the live values" % mode)


func test_the_third_record_shares_the_second_ones_buffer() -> void:
	var replay := ReplayState.new()
	var second := _fighter(1)
	var third := _fighter(2)
	replay.mode = ReplayState.RECORDING
	second.hands.current = PackedInt32Array([0x100, 0x100])
	replay.hand_levels(second)
	replay.mode = ReplayState.PLAYING
	expect_equal(replay.hand_levels(third), PackedInt32Array([0x100, 0x100]), "as the game's other replay hooks")


func test_shown_is_the_replays_values_while_it_plays() -> void:
	var hands := FighterHands.new()
	hands.current = PackedInt32Array([0, 0])
	expect_equal(hands.shown(), PackedInt32Array([0, 0]), "the live values with no replay")
	hands.replay_levels = PackedInt32Array([0x200, 0x203])
	expect_equal(hands.shown(), PackedInt32Array([0x200, 0x203]), "the recorded values in the replay")
	expect_equal(hands.current, PackedInt32Array([0, 0]), "the live ones are left alone")
	hands.replay_levels = PackedInt32Array()
	expect_equal(hands.shown(), PackedInt32Array([0, 0]), "and back to the live ones")
