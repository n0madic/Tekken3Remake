extends TestSuite
## A mode's start (ModeStart, FUN_800DAF2C): the fighter records get their own numbers again.


## Tekken Ball copies a hitter's whole record into the third record, pad slot included; the next
## mode (Tekken Force's enemy 1 on player 1's move rows) must not keep it.
func test_records_get_their_numbers_again() -> void:
	var flow := imported_flow()
	if flow == null:
		return
	var fighters := flow.fight.fighters
	fighters[2].copy_from(fighters[0])
	fighters[1].player_index = 0
	expect_equal(fighters[2].player_index, 0, "the copy carries the hitter's pad slot")
	ModeStart.start(flow, GameMode.FORCE, 1)
	for i in 3:
		expect_equal(fighters[i].player_index, mini(i, 1), "record %d: pad slot" % i)
		expect_equal(fighters[i].index, i, "record %d: index" % i)


## Issue #27: the preparation (and the fight's own loading) shows no fight: the fight view still
## holds the last fight, which must not flash in front of the next screen. The rounds and what
## follows them show it.
func test_only_the_running_fight_is_shown() -> void:
	var flow := imported_flow()
	if flow == null:
		return
	ModeStart.start(flow, GameMode.VS, 2)
	expect_equal(flow.state, GameFlow.State.PREPARE, "a mode starts through the preparation")
	for sub: int in 4:
		flow.sub = sub
		expect(not flow.showing_fight(), "preparation sub-state %d shows no fight" % sub)
	flow.state = GameFlow.State.FIGHT
	for sub: int in MatchFlow.Sub.ROUND_START:
		flow.sub = sub
		expect(not flow.showing_fight(), "fight sub-state %d (selecting, loading) shows no fight" % sub)
	for sub: int in [MatchFlow.Sub.ROUND_START, MatchFlow.Sub.FIGHT, MatchFlow.Sub.GAME_OVER, MatchFlow.Sub.OGRE]:
		flow.sub = sub
		expect(flow.showing_fight(), "fight sub-state %d shows the fight" % sub)
	for state: int in [GameFlow.State.VS, GameFlow.State.SELECT, GameFlow.State.MENU, GameFlow.State.LOADER]:
		flow.state = GameFlow.target_state(state)
		flow.sub = MatchFlow.Sub.FIGHT
		expect(not flow.showing_fight(), "state %d shows no fight" % state)
