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
