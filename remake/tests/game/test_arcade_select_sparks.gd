extends TestSuite
## The character select's sparks: when they start, where, how they rise and when they end. The traces of
## tests/game/test_arcade_flow_traces.gd prove them against the program; these name the rules.

const Y := 200
const CLOCK := 1000

var X := PackedInt32Array([0x10, 0x100])


func _fight() -> FightState:
	var fight := FightState.new(null, RuleSet.original())
	fight.frame_rng = 1
	return fight


func _active(sparks: ArcadeSelectSparks) -> Array[SelectSparks.Spark]:
	var out: Array[SelectSparks.Spark] = []
	for s: SelectSparks.Spark in sparks.sparks:
		if s.active != 0:
			out.append(s)
	return out


func test_one_starts_every_fourth_frame() -> void:
	var sparks := ArcadeSelectSparks.new()
	var fight := _fight()
	sparks.step(1, CLOCK, X, Y, fight)
	expect_equal(_active(sparks).size(), 0, "not on an odd frame")
	var random := fight.rng.state
	sparks.step(8, CLOCK, X, Y, fight)
	expect_equal(_active(sparks).size(), 1, "on a multiple of four")
	expect_equal(fight.frame_rng, 31, "two steps of the frame generator: where it starts, then its fade")
	expect_equal(fight.rng.state, random, "rand is not theirs")


func test_the_sides_take_turns_over_the_portrait() -> void:
	for frame: int in [0, 4]:
		var sparks := ArcadeSelectSparks.new()
		sparks.step(frame, CLOCK, X, Y, _fight())
		var x := _active(sparks)[0].x
		var side := 1 if frame == 4 else 0
		expect(x >= X[side] and x < X[side] + ArcadeSelectSparks.PORTRAIT_WIDTH, "frame %d rises over side %d: %d" % [frame, side, x])


func test_a_spark_rises_by_the_clock_and_fades_out() -> void:
	var sparks := ArcadeSelectSparks.new()
	var fight := _fight()
	sparks.step(4, CLOCK, X, Y, fight)
	var s := _active(sparks)[0]
	expect_equal(s.y, Y, "starts at the plates")
	var fade := s.fade
	expect(fade >= ArcadeSelectSparks.FADE_MIN and fade <= ArcadeSelectSparks.FADE_MIN + 3, "fade %d" % fade)
	expect_equal(s.brightness, ArcadeSelectSparks.START_BRIGHTNESS - fade, "fades from its first step")
	sparks.step(5, CLOCK + 2, X, Y, fight)
	expect_equal(s.y, Y - 2 * SelectSparks.RISE, "two displayed frames higher")
	var clock := CLOCK + 2
	var frame := 5
	while s.active != 0 and frame < 100:
		frame += 2
		clock += 1
		sparks.step(frame, clock, X, Y, fight)
	expect(s.active == 0, "it ends")
	expect(s.brightness < 1 or s.y + SelectSparks.LENGTH < 0, "dark or above the screen")


func test_the_pool_is_limited_and_cleared() -> void:
	var sparks := ArcadeSelectSparks.new()
	var fight := _fight()
	for s: SelectSparks.Spark in sparks.sparks:
		s.active = 1
		s.started = 1
		s.brightness = ArcadeSelectSparks.START_BRIGHTNESS
		s.first_y = Y
	sparks.step(4, CLOCK, X, Y, fight)
	expect_equal(fight.frame_rng, 1, "none free: no spark starts, no number is drawn")
	sparks.clear()
	expect_equal(_active(sparks).size(), 0, "the select's set-up empties it")
