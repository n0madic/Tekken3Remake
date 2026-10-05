extends TestSuite
## The remake's Escape on a pause menu (GameFlow.escape_pressed): pending through the menu's inert
## frames, dropped once it is taken or the menu has left its list.


func _paused_flow() -> GameFlow:
	var flow := imported_flow()
	if flow == null:
		return null
	flow.state = GameFlow.State.FIGHT
	flow.region.mode = GameMode.BALL
	flow.fight.paused_player = 1
	flow.fight.pause_cursor = 0
	flow.escape_pressed = true
	return flow


## Escape pressed on Tekken Ball's HOW TO page does nothing, and does not close the whole menu
## later, when the page is left.
func test_escape_does_not_wait_for_how_to_to_close() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _paused_flow()
	flow.fight.pause_page = PauseMenu.PAGE_HOW_TO
	flow._update_escape()
	expect(not flow.escape_pressed, "dropped while the HOW TO page is up")
	flow.fight.pause_page = 0
	flow._update_escape()
	flow._update_escape()
	expect_equal(flow.fight.pause_page, 0, "the menu is not cancelled when the page closes")
	expect_equal(flow.fight.pause_delay, 0, "and not left for its exit")


func test_escape_waits_through_inert_frames() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _paused_flow()
	flow.fight.pause_delay = 2
	flow._update_escape()
	expect(flow.escape_pressed, "pending while the menu is inert")
	expect_equal(flow.fight.pause_page, 0, "untouched")
	flow.fight.pause_delay = 0
	flow._update_escape()
	expect(not flow.escape_pressed, "taken once it listens")
	expect_equal(flow.fight.pause_page, PauseMenu.PAGE_CANCEL, "as CANCEL")


func test_escape_is_dropped_with_the_menu() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _paused_flow()
	flow.fight.paused_player = 0
	flow._update_escape()
	expect(not flow.escape_pressed, "no menu, no pending Escape")
	expect_equal(flow.fight.pause_page, 0, "nothing happened")


func _fighting_flow() -> GameFlow:
	var flow := imported_flow()
	if flow == null:
		return null
	flow.state = GameFlow.State.FIGHT
	flow.region.mode = GameMode.ARCADE
	flow.fight.pause_allowed = 1
	flow.fight.round_state = RoundState.FIGHT
	flow.fight.human_mask = 1
	return flow


## The pad the focus loss presses Start on: the first human's, and none where no Start would pause.
func test_pause_pad_is_the_first_human() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	expect_equal(flow.pause_pad(), 0, "player 1 alone")
	flow.fight.human_mask = 3
	expect_equal(flow.pause_pad(), 0, "two humans: player 1")
	flow.fight.human_mask = 2
	expect_equal(flow.pause_pad(), 1, "player 2 alone")
	flow.fight.human_mask = 0
	expect_equal(flow.pause_pad(), -1, "no human (the demonstration)")


func test_pause_pad_waits_for_an_open_fight() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	flow.fight.round_state = RoundState.INTRO
	expect_equal(flow.pause_pad(), -1, "the round intro")
	flow.fight.round_state = RoundState.REPLAY
	expect_equal(flow.pause_pad(), -1, "the replay after a KO")
	flow.fight.round_state = RoundState.FIGHT
	flow.fight.pause_allowed = 0
	expect_equal(flow.pause_pad(), -1, "a mode that does not pause")
	flow.fight.pause_allowed = 1
	flow.state = GameFlow.State.MENU
	expect_equal(flow.pause_pad(), -1, "outside a fight")


func test_pause_pad_is_none_once_paused() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	flow.fight.pause_request = 1
	expect_equal(flow.pause_pad(), -1, "asked for")
	flow.fight.pause_request = 0
	flow.fight.paused_player = 1
	expect_equal(flow.pause_pad(), -1, "open")


## Practice pauses on its own player's Start, and not while a replay plays.
func test_pause_pad_in_practice() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	flow.region.mode = GameMode.PRACTICE
	flow.fight.tie_choice = 1
	expect_equal(flow.pause_pad(), 1, "the practising player")
	flow.fight.replay_playing = 1
	expect_equal(flow.pause_pad(), -1, "a replay")


## A tap is Start of the pad the human plays on: a Start from the other pad would join a
## challenger.
func test_tap_goes_to_the_human() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	expect_equal(flow.tap_pad(), 0, "player 1 alone")
	flow.fight.human_mask = 2
	expect_equal(flow.tap_pad(), 1, "player 2 alone, not a challenger on player 1's pad")
	flow.fight.human_mask = 3
	expect_equal(flow.tap_pad(), 0, "two humans")
	flow.fight.human_mask = 0
	expect_equal(flow.tap_pad(), 0, "the demonstration: Start leaves it on player 1's pad")


## The click that brings the window back to an open pause does not resume the fight.
func test_tap_does_nothing_in_a_pause() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	flow.fight.human_mask = 2
	flow.fight.pause_request = 2
	flow.fight.paused_player = 2
	expect_equal(flow.tap_pad(), -1, "pause open")
	flow.fight.pause_request = 0
	flow.fight.paused_player = 0
	expect_equal(flow.tap_pad(), 1, "pause closed")


func test_tap_outside_a_fight_is_player_one() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	flow.fight.human_mask = 2
	flow.state = GameFlow.State.MENU
	expect_equal(flow.tap_pad(), 0, "menus")


## Escape presses for the fight's human when the keyboard's player does not play there, and for the
## keyboard's player otherwise (VS, outside fights, the demonstration).
func test_escape_pad_is_the_fight_human() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _fighting_flow()
	expect_equal(flow.escape_pad(1), 0, "arcade on pad 1, keyboard on side 2: Escape pauses for pad 1")
	expect_equal(flow.escape_pad(0), -1, "the keyboard's player plays: its own pad")
	flow.fight.human_mask = 3
	expect_equal(flow.escape_pad(1), -1, "VS: both play, the keyboard's own pad")
	flow.fight.human_mask = 0
	expect_equal(flow.escape_pad(1), -1, "no human (the demonstration)")
	flow.region.mode = GameMode.PRACTICE
	flow.fight.tie_choice = 1
	expect_equal(flow.escape_pad(0), 1, "practice: its player's pad")
	expect_equal(flow.escape_pad(1), -1, "practice played on the keyboard's side")
	flow.state = GameFlow.State.MENU
	expect_equal(flow.escape_pad(1), -1, "outside a fight: the keyboard's player")
