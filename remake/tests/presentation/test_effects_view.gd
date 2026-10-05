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
