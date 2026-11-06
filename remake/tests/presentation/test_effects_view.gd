extends TestSuite
## EffectsView runs the flipbooks as the simulation's EFFECTS_DRAW says: they advance on
## EFFECTS_ADVANCE, hold on EFFECTS_HOLD (pause), are hidden on steps without EFFECTS_DRAW (the
## loser camera), and all end on EFFECTS_CLEAR; ended sprites are reused.


func test_flipbooks_follow_the_draw_events() -> void:
	var data := EffectData.new()
	var book := EffectData.Flipbook.new()
	book.frames = 5
	data.system.append(book)
	var view := EffectsView.new()
	view.setup(data)
	var events := SimEvents.new()
	events.add_at(SimEvents.Kind.SPARK, -1, PackedInt32Array([0, 0, 0]), 0)
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
	view.step(events)
	expect_equal(view.sprites.size(), 1, "the spark starts")
	var sprite := view.sprites[0]
	var frame := sprite.frame
	_step(view, events, SimEvents.EFFECTS_HOLD)
	expect_equal(sprite.frame, frame, "EFFECTS_HOLD (pause) holds it")
	expect(view.flipbooks.visible, "a held spark is drawn")
	events.clear()
	view.step(events)
	expect_equal(sprite.frame, frame, "a step that does not draw it does not advance it")
	expect(not view.flipbooks.visible, "a step without EFFECTS_DRAW hides it")
	_step(view, events, SimEvents.EFFECTS_ADVANCE)
	expect_equal(sprite.frame, frame + 1, "EFFECTS_ADVANCE advances it")
	events.clear()
	events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	view.step(events)
	expect_equal(view.sprites.size(), 0, "EFFECTS_CLEAR ends it")
	events.clear()
	events.add_at(SimEvents.Kind.SPARK, -1, PackedInt32Array([0, 0, 0]), 0)
	view.step(events)
	expect(view.sprites[0] == sprite, "the next spark reuses the ended sprite")
	view.free()


static func _step(view: EffectsView, events: SimEvents, mode: int) -> void:
	events.clear()
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, mode)
	view.step(events)


func test_drift_fades_each_frame() -> void:
	var data := EffectData.new()
	var book := EffectData.Flipbook.new()
	book.frames = 30
	data.system.append(book)
	var view := EffectsView.new()
	view.setup(data)
	var events := SimEvents.new()
	var spark := events.add_at(SimEvents.Kind.HIT_SPARK, 0, PackedInt32Array([0, 0, 0]), 0)
	spark.vector = PackedInt32Array([0, 0, 4096])
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
	view.step(events)
	expect_equal(view.sprites.size(), 1, "the hit spark starts")
	var sprite := view.sprites[0]
	var start := sprite.node.position
	var first := sprite.velocity.length()
	for i in 10:
		_step(view, events, SimEvents.EFFECTS_ADVANCE)
	expect_equal(snappedf(sprite.velocity.length() / first, 0.0001), snappedf(pow(EffectsView.DRIFT_DECAY, 10.0), 0.0001), "the speed decays by 0x76/128 a frame")
	expect((sprite.node.position - start).length() < first * 10.0, "the sprite drifts less than at a constant speed")
	view.free()


func test_a_mirrored_spark_is_read_from_the_right_edge_of_its_frame() -> void:
	var data := EffectData.new()
	var book := EffectData.Flipbook.new()
	book.frames = 4
	data.system.append(book)
	var view := EffectsView.new()
	view.setup(data)
	var events := SimEvents.new()
	var plain := events.add_at(SimEvents.Kind.HIT_SPARK, 0, PackedInt32Array([0, 0, 0]), 0)
	plain.vector = PackedInt32Array([100, 0, 0])
	var flipped := events.add_at(SimEvents.Kind.HIT_SPARK, 1, PackedInt32Array([0, 0, 0]), 0)
	flipped.vector = PackedInt32Array([100, 0, 0])
	flipped.mirrored = true
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
	view.step(events)
	var a := view.sprites[0].material
	var b := view.sprites[1].material
	# The first frame is the texture's first quarter: the plain sprite reads u 0 → 1/4 over it,
	# the mirrored one 1/4 → 0.
	expect_equal(a.uv1_scale.x, 0.25, "a plain sprite spans a frame left to right")
	expect_equal(a.uv1_offset.x, 0.0, "from the frame's left edge")
	expect_equal(b.uv1_scale.x, -0.25, "a mirrored sprite spans it right to left")
	expect_equal(b.uv1_offset.x, 0.25, "from the frame's right edge")
	_step(view, events, SimEvents.EFFECTS_ADVANCE)
	expect_equal(a.uv1_offset.x, 0.25, "the second frame, plain")
	expect_equal(b.uv1_offset.x, 0.5, "and mirrored: the same frame, read the other way")
	view.free()


func test_sparks_the_game_draws_over_the_ball_are_placed_clear_of_it() -> void:
	var eye := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var ball := Vector4(0, 0, -5, 0.5)       # 5 m ahead, 0.5 m radius: its surface starts 4.5 m ahead
	var front := 5.0 - 0.5 - EffectsView.BALL_MARGIN
	var at := Vector3(0.1, 0.2, -5.0)         # at the ball's depth, inside the sphere's reach
	var k := EffectsView.pull_over_ball(eye, forward, at, ball)
	expect(k < 1.0, "a spark at the ball's depth is pulled toward the camera")
	expect(is_equal_approx(-(at * k).z, front), "to just in front of the sphere")
	expect((at * k).normalized().is_equal_approx(at.normalized()), "along its view ray, so it stays where it was on the screen")
	var inside := EffectsView.pull_over_ball(eye, forward, Vector3(0, 0, -(5.0 + EffectsView.SORT_BIAS - 0.01)), ball)
	expect(inside < 1.0, "also one up to the sort bias behind the ball's centre: the game files it over the ball")
	var behind := EffectsView.pull_over_ball(eye, forward, Vector3(0, 0, -(5.0 + EffectsView.SORT_BIAS + 0.01)), ball)
	expect_equal(behind, 1.0, "one beyond it is behind the ball, as in the game")
	expect_equal(EffectsView.pull_over_ball(eye, forward, Vector3(0, 0, -4.0), ball), 1.0, "one already in front of the sphere stays")
	expect_equal(EffectsView.pull_over_ball(eye, forward, Vector3(3, 0, -5.0), ball), 1.0, "and one too far aside to touch it")
	expect_equal(EffectsView.pull_over_ball(eye, forward, at, Vector4.ZERO), 1.0, "without a solid ball nothing moves")


func test_place_pulls_a_spark_and_lets_it_go() -> void:
	var data := EffectData.new()
	var book := EffectData.Flipbook.new()
	book.frames = 5
	data.system.append(book)
	var view := EffectsView.new()
	view.setup(data)
	var events := SimEvents.new()
	events.add_at(SimEvents.Kind.SPARK, -1, PackedInt32Array([0, 0, 5000]), 0)     # 5 m ahead of the camera
	view.step(events)
	var sprite := view.sprites[0]
	var eye := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	view.place(eye, forward, Vector4(0, 0, -5, 0.5))
	expect(sprite.node.scale.x < 1.0 and sprite.node.position.z > sprite.at.z, "pulled toward the camera and scaled down")
	expect_equal(sprite.at, Vector3(0, 0, -5), "its place in the world unchanged")
	view.place(eye, forward, Vector4.ZERO)
	expect_equal(sprite.node.position, sprite.at, "back where it is when the ball goes")
	expect_equal(sprite.node.scale, Vector3.ONE, "at full size")
	view.free()
