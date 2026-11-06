extends TestSuite
## The two character select screens' drawing decisions: a side with nothing chosen shows the
## silhouette, and the quick select's name is drawn over its plate.

## A quick select that records the order of its plate and text.
class Recorder extends QuickSelectView:
	var calls: Array[String] = []

	func _name_plate(_x: int, _y: int, _w: int, colour: int) -> void:
		calls.append("plate %d" % colour)

	func text(s: String, _font_index: int, _colour: int, _x: float, _y: float, _alpha := 1.0) -> void:
		calls.append("text " + s)


func test_a_side_with_no_choice_shows_the_silhouette() -> void:
	var game := imported_flow()
	if game == null:
		return
	var count := GameProgress.CHARACTERS
	var silent := SelectView.side_attribute(game.data, CharacterSelect.NO_CELL, 0, count)
	expect_equal(silent & 0x1F, 0x15, "the empty side's picture is the 22nd")
	expect_equal(silent, SelectView.SUBTRACTED_PORTRAIT, "drawn subtracted, as the silhouette")
	expect_equal(SelectView.side_attribute(game.data, CharacterSelect.NO_CELL + 5, 3, count), silent,
		"any out-of-range key and costume do the same")
	expect_equal(SelectView.side_attribute(game.data, 3, 1, count) & 0x1F, 3, "a character shows its own portrait")
	expect_equal(SelectView.side_attribute(game.data, CharacterSelect.NO_CELL, 0, 0x15), -1,
		"no picture for it: nothing is drawn")


func test_a_costume_with_a_name_of_its_own_shows_it() -> void:
	var game := imported_flow()
	if game == null:
		return
	var tables := game.fight.tables
	expect_equal(QuickSelectView.character_name(tables, 11 * 4), "KUMA", "Kuma's first costume")
	expect_equal(QuickSelectView.character_name(tables, 11 * 4 + 1), "PANDA", "Kuma's second is Panda")
	expect_equal(QuickSelectView.character_name(tables, 8 * 4 + 2), "TIGER", "Eddy's third is Tiger")
	expect_equal(QuickSelectView.character_name(tables, 5 * 4 + 2), "ANNA", "Nina's third is Anna")
	expect_equal(QuickSelectView.character_name(tables, 3), "PAUL", "a costume without a name of its own keeps the character's")
	expect_equal(QuickSelectView.character_name(tables, -1), "", "no key, no name")


func test_quick_select_name_is_drawn_over_its_plate() -> void:
	var view := Recorder.new()
	view._name("XIAOYU", 6, 100, 50, 2)
	expect_equal(view.calls, ["plate 2", "text XIAOYU"] as Array[String], "the plate first, then the letters over it")
	view.calls.clear()
	view._name("NO ENTRY", 9, 100, 50, -1)
	expect_equal(view.calls, ["text NO ENTRY"] as Array[String], "a message has no plate")
	view.free()
