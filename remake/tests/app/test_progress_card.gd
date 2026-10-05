extends TestSuite
## The memory cards: two save files, AUTO SAVE on for a fresh card, the options saved on leaving
## OPTIONS while auto save is (or was) on, and a replay's card never written.

## One file pair per test: the runners may run the tests at the same time.
const PATH := "user://test_card_%s_%d.json"


func _card(test: String) -> ProgressCard:
	var c := ProgressCard.new()
	var p := GameProgress.new(GameProgress.SIZE)
	p.difficulty = 2
	c.defaults = p.save_data()
	c.select(1)
	c.store.progress_path = PATH % [test, 1]
	return c


func _remove(test: String) -> void:
	for n: int in [1, 2]:
		DirAccess.remove_absolute(PATH % [test, n])


func test_cards_have_their_own_files() -> void:
	expect_equal(ProgressCard.path_for(1), "user://progress.json")
	expect_equal(ProgressCard.path_for(2), "user://progress2.json")
	expect_equal(ProgressCard.path_for(7), "user://progress2.json")


func test_fresh_card_starts_with_auto_save() -> void:
	var c := _card("fresh")
	_remove("fresh")
	var p := GameProgress.new(GameProgress.SIZE)
	p.difficulty = 4
	c.load_into(p)
	expect_equal(p.difficulty, 2, "defaults")
	expect_equal(p.auto_save, 1, "auto save on")
	c.auto_save_default = false
	c.load_into(p)
	expect_equal(p.auto_save, 0, "the game's default with --fresh")


func test_saved_card_loads_its_progress() -> void:
	var c := _card("load")
	var p := GameProgress.new(GameProgress.SIZE)
	c.fresh_progress(p)
	p.auto_save = 0
	p.difficulty = 3
	expect_equal(c.write(p.save_data()), SaveStore.CARD_DONE)
	var q := GameProgress.new(GameProgress.SIZE)
	c.load_into(q)
	expect_equal(q.difficulty, 3)
	expect_equal(q.auto_save, 0, "turned off stays off")
	c.reads = false
	c.load_into(q)
	expect_equal(q.difficulty, 2, "--fresh ignores the save")
	_remove("load")


func test_options_saved_while_auto_save_is_or_was_on() -> void:
	var c := _card("options")
	_remove("options")
	var p := GameProgress.new(GameProgress.SIZE)
	c.load_into(p)
	expect(c.saves_options(p), "on")
	c.write(p.save_data())
	p.auto_save = 0
	expect(c.saves_options(p), "just turned off: the card still has it on")
	c.write(p.save_data())
	expect(not c.saves_options(p), "off in the card too")
	_remove("options")


func test_replay_card_is_never_written() -> void:
	var c := _card("replay")
	_remove("replay")
	c.writes = false
	var p := GameProgress.new(GameProgress.SIZE)
	expect_equal(c.write(p.save_data()), SaveStore.CARD_DONE)
	expect(not FileAccess.file_exists(PATH % ["replay", 1]))


## A card whose defaults are the game's: the ten first characters and Law's Start costume.
func _locked_card(test: String) -> ProgressCard:
	var c := _card(test)
	var p := GameProgress.new(GameProgress.SIZE)
	p.unlocked = 0x3FF
	p.start_costumes = 0x2
	c.defaults = p.save_data()
	return c


func test_unlock_opens_everything_in_memory() -> void:
	var c := _locked_card("unlock_open")
	_remove("unlock_open")
	c.unlock_all = true
	var p := GameProgress.new(GameProgress.SIZE)
	c.load_into(p)
	expect_equal(p.unlocked, ProgressRules.ALL_CHARACTERS, "characters")
	expect_equal(p.start_costumes, 0x2 | ProgressRules.START_COSTUME_MASK, "Start costumes")
	expect(p.ball_new != 0 and p.theater_new != 0, "Tekken Ball and Theater")
	expect_equal(p.unlock_class, 2, "every character")
	expect_equal(p.cleared, ProgressRules.ALL_CHARACTERS, "the clears that open Theater's movies")
	expect_equal(p.cleared2, ProgressRules.SECOND_CLEARS, "the second clears")
	c.unlock_all = false
	c.load_into(p)
	expect_equal(p.unlocked, 0x3FF, "without --unlock the defaults stay")
	expect_equal(p.ball_new, 0)
	expect_equal(p.cleared, 0)


func test_unlock_is_read_over_a_saved_card() -> void:
	var c := _locked_card("unlock_read")
	_remove("unlock_read")
	var p := GameProgress.new(GameProgress.SIZE)
	c.fresh_progress(p)
	p.unlocked = 0x7FF
	c.write(p.save_data())
	c.unlock_all = true
	c.load_into(p)
	expect_equal(p.unlocked, ProgressRules.ALL_CHARACTERS)
	expect_equal(c.read().size(), GameProgress.SAVE_BLOCK + GameProgress.RECORDS_SIZE)
	_remove("unlock_read")


func test_unlock_is_never_written() -> void:
	var c := _locked_card("unlock_save")
	_remove("unlock_save")
	c.unlock_all = true
	var p := GameProgress.new(GameProgress.SIZE)
	c.load_into(p)
	p.difficulty = 3
	p.set_stat(0, 0, 7)
	p.fights_since_unlock = 40
	p.play_steps = 3
	p.cleared2 |= 0x2000
	expect_equal(c.write(p.save_data()), SaveStore.CARD_DONE)
	var q := GameProgress.new(GameProgress.SIZE)
	var plain := _locked_card("unlock_save")
	plain.load_into(q)
	expect_equal(q.difficulty, 3, "the rest of the progress is saved")
	expect_equal(q.stat(0, 0), 7, "the statistics too")
	expect_equal(q.unlocked, 0x3FF, "characters")
	expect_equal(q.start_costumes, 0x2, "Start costumes")
	expect_equal(q.ball_new, 0, "Tekken Ball")
	expect_equal(q.theater_new, 0, "Theater")
	expect_equal(q.unlock_class, 0)
	expect_equal(q.cleared, 0, "the arcade clears")
	expect_equal(q.cleared2, 0, "the second clears")
	expect_equal(q.fights_since_unlock, 0, "the play count of the unlock schedule")
	expect_equal(q.play_steps, 0)
	_remove("unlock_save")


func test_unlock_keeps_what_the_card_had_unlocked() -> void:
	var c := _locked_card("unlock_kept")
	_remove("unlock_kept")
	var p := GameProgress.new(GameProgress.SIZE)
	c.fresh_progress(p)
	p.unlocked = 0x7FF
	p.ball_new = 2
	p.cleared = 0x3
	c.write(p.save_data())
	c.unlock_all = true
	c.load_into(p)
	c.write(p.save_data())
	c.unlock_all = false
	c.load_into(p)
	expect_equal(p.unlocked, 0x7FF, "a real unlock survives an --unlock session")
	expect_equal(p.ball_new, 2)
	expect_equal(p.cleared, 0x3, "the real clears too")
	_remove("unlock_kept")
