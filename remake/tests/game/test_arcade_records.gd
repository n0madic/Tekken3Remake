extends TestSuite
## The arcade's records: the play counts, the versus wins' table and the in-fight name entry of a versus
## record (FUN_801B9138). The flow traces of test_arcade_flow_traces.gd do not reach the in-fight entry;
## these name its rules as the program has them.

const STREAK := 50
const RIGHT := ArcadeInput.PANEL_RIGHT

var _content: ArcadeFightContent
var _data: ArcadeFlowData


func _flow() -> ArcadeGameFlow:
	if not Assets.arcade_only():
		skip("not a conversion from the arcade set")
		return null
	if _content == null:
		_content = ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
		_data = ArcadeFlowData.load_from(AssetCatalog.ROOT.path_join(ArcadeFlowData.FILE))
	return ArcadeGameFlow.new(_content, _data, RuleSet.original(), ArcadeSettings.new(), 1)


## One frame of the entry with player 1's panel word.
func _entry_frame(flow: ArcadeGameFlow, entry: ArcadeNameEntry, word: int) -> void:
	flow.sim.panels.read(PackedInt32Array([word, 0]))
	entry.step(flow)


func test_a_play_count_stops_at_a_u16s_largest() -> void:
	var progress := ArcadeProgress.new()
	progress.plays[5] = ArcadeProgress.COUNT_MAX
	progress.plays[6] = 3
	progress.count_play(5)
	progress.count_play(6)
	expect_equal(progress.plays[5], ArcadeProgress.COUNT_MAX, "FUN_801B93E8 saturates")
	expect_equal(progress.plays[6], 4, "and counts below it")


func test_the_entry_times_up_300_frames_after_the_last_input() -> void:
	var flow := _flow()
	if flow == null:
		return
	var entry := flow.match_flow.name_entry
	entry.begin(flow, 0, 0, STREAK)
	expect_equal(entry.phase, ArcadeNameEntry.ACTIVE, "the streak makes a place")
	for i in ArcadeNameEntry.BUTTON_FRAMES:
		_entry_frame(flow, entry, 0)
	expect_equal(entry.phase, ArcadeNameEntry.ACTIVE, "300 frames without input still enter")
	_entry_frame(flow, entry, 0)
	expect_equal(entry.phase, ArcadeNameEntry.SHOWN_DONE, "the 301st times up")


func test_moving_along_the_alphabet_keeps_the_entry_open() -> void:
	var flow := _flow()
	if flow == null:
		return
	var entry := flow.match_flow.name_entry
	entry.begin(flow, 0, 0, STREAK)
	for i in ArcadeNameEntry.BUTTON_FRAMES + 100:
		_entry_frame(flow, entry, RIGHT if i % 2 == 0 else 0)
	expect_equal(entry.phase, ArcadeNameEntry.ACTIVE, "each move restarts the wait (the block at 0x801B9194)")
	expect(entry.button_wait <= 2, "the wait restarted: %d" % entry.button_wait)


func test_the_entered_name_shows_for_61_frames() -> void:
	var flow := _flow()
	if flow == null:
		return
	var entry := flow.match_flow.name_entry
	entry.begin(flow, 0, 0, STREAK)
	_entry_frame(flow, entry, ArcadeGameFlow.START)
	expect_equal(entry.phase, ArcadeNameEntry.SHOWN_DONE, "Start ends the entry")
	for i in ArcadeNameEntry.DONE_FRAMES + 1:
		_entry_frame(flow, entry, 0)
	expect_equal(entry.phase, ArcadeNameEntry.SHOWN_DONE, "shown while the old count is up to 0x3B")
	_entry_frame(flow, entry, 0)
	expect_equal(entry.phase, 0, "gone on the frame after")


func test_a_streak_without_a_place_stores_nothing() -> void:
	var flow := _flow()
	if flow == null:
		return
	for row: ArcadeProgress.Row in flow.progress.wins:
		row.count = STREAK * 2
	var before: Array = flow.progress.saved_records()["wins"]
	flow.ranking.store_wins(0, STREAK, "ABC")
	expect_equal(flow.progress.saved_records()["wins"], before, "FUN_801B4AD4 returns when the streak makes no place")
	flow.ranking.store_wins(0, STREAK * 3, "ABC")
	expect_equal(flow.progress.wins[0].name, "ABC", "a longer streak takes the first row")


func test_a_new_game_ends_an_entry_still_shown() -> void:
	var flow := _flow()
	if flow == null:
		return
	flow.match_flow.name_entry.phase = ArcadeNameEntry.SHOWN_DONE
	flow.start_mode(ArcadeGameFlow.MODE_ARCADE, 1)
	expect_equal(flow.match_flow.name_entry.phase, 0, "FUN_801B901C")


## The ranking's entry clicks as the select screen does (the blocks at 0x801C2AFC, 0x801C2B18).
func test_the_rankings_entry_sounds_its_moves_and_letters() -> void:
	var flow := _flow()
	if flow == null:
		return
	flow.state = ArcadeGameFlow.State.RANKING
	flow.sub = 0xD
	flow.attract_silent = 0
	var ranking := flow.ranking
	ranking.pending = ArcadeRanking.PENDING_TIME
	ranking.time_row = 0
	ranking.page_clock = ArcadeRanking.NAME_FRAMES
	ranking.entry.open(0, 0)
	flow.step(RIGHT, 0)
	expect_equal(_system_sounds(flow), PackedInt32Array([ArcadeSelect.MOVE_SOUND]), "a move")
	flow.step(0, 0)
	expect_equal(_system_sounds(flow), PackedInt32Array(), "nothing without input")
	flow.step(ArcadeInput.LP, 0)
	expect_equal(_system_sounds(flow), PackedInt32Array([ArcadeSelect.PICK_SOUND]), "a letter")


func _system_sounds(flow: ArcadeGameFlow) -> PackedInt32Array:
	var out := PackedInt32Array()
	for e: SimEvents.Event in flow.sim.events.items:
		if e.kind == SimEvents.Kind.SYSTEM_SOUND and e.b == ArcadeSelect.MOVE_CHANNEL:
			out.append(e.a)
	return out
