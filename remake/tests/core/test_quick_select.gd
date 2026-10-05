extends TestSuite
## The resident character select (QuickSelect): Select takes the last pick back.


func _flow() -> GameFlow:
	return imported_flow()


## The picks are members 0 to count − 1: Select gives back the last one, not the slot after it.
func test_select_gives_the_last_pick_back() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return
	var flow := _flow()
	var q := flow.quick
	var everyone := 0x3FFFFF
	var paul := 0 * 4 + 0
	var law := 1 * 4 + 1
	q.w32(0, QuickSelect.R_COUNT, 2)
	q.w32(0, QuickSelect.R_MEMBERS, paul)
	q.w32(0, QuickSelect.R_MEMBERS + 4, law)
	q.w32(0, QuickSelect.R_AVAILABLE, everyone & ~(1 << 0) & ~(1 << 1))
	expect(q._undo(0), "a pick to take back")
	expect_equal(q.r32(0, QuickSelect.R_COUNT), 1, "one pick left")
	expect_equal(q.rs32(0, QuickSelect.R_MEMBERS), paul, "the first pick stays")
	expect_equal(q.rs32(0, QuickSelect.R_MEMBERS + 4), QuickSelect.LOCKED, "the last slot is empty again")
	expect_equal(q.rs32(0, QuickSelect.R_LAST), law, "the cursor goes back to the taken pick")
	expect_equal(q.r32(0, QuickSelect.R_AVAILABLE), everyone & ~1, "Law is free again, Paul still taken")
	expect(q._undo(0), "the first pick too")
	expect_equal(q.r32(0, QuickSelect.R_COUNT), 0, "no picks left")
	expect_equal(q.r32(0, QuickSelect.R_AVAILABLE), everyone, "everyone is free")
	expect(not q._undo(0), "nothing more to take back")
