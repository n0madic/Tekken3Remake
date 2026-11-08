extends TestSuite
## The attract movie's time in ArcadeGameFlow against MAME's frames (arcade_movie_capture.lua: sub-state
## 2 from frame 8527, sub-state 9 from frame 9579, the title's picture from frame 9583), and the
## view without its files. Needs a conversion from MAME's set alone; skipped otherwise.

const VBLANKS_IN_SUB_STATE_2 := 1052
const VBLANKS_OF_THE_MOVIE_FRAMES := 1056
const LAST_TIMER := 263
const SUB_MOVIE_START := 1
const SUB_TITLE := 9

var _content: ArcadeFightContent
var _data: ArcadeFlowData


func _flow() -> ArcadeGameFlow:
	if not require(AssetCatalog.ROOT.path_join("tables/arcade_flow.json")):
		return null
	if not Assets.arcade_only():
		skip("not a conversion from the arcade set")
		return null
	if _content == null:
		_content = ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
		_data = ArcadeFlowData.load_from(AssetCatalog.ROOT.path_join("tables/arcade_flow.json"))
	var flow := ArcadeGameFlow.new(_content, _data, RuleSet.original(), ArcadeSettings.new(), 1)
	flow.state = ArcadeGameFlow.State.ATTRACT
	flow.attract_step = ArcadeGameFlow.ATTRACT_MOVIE
	flow.sub = 0
	return flow


func test_the_movie_lasts_as_in_mame() -> void:
	var flow := _flow()
	if flow == null:
		return
	flow.step(0, 0)
	expect_equal(flow.frame_vblanks(), 1, "the black frame before the movie")
	expect_equal(flow.sub, SUB_MOVIE_START)
	var vblanks := 0
	var vblanks_in_two := 0
	var last_timer := -1
	while flow.picture != ArcadeGameFlow.Picture.TITLE:
		flow.step(0, 0)
		if flow.picture == ArcadeGameFlow.Picture.MOVIE:
			vblanks += flow.frame_vblanks()
			last_timer = flow.timer
			if flow.sub != SUB_TITLE:
				vblanks_in_two += flow.frame_vblanks()
	expect_equal(vblanks, VBLANKS_OF_THE_MOVIE_FRAMES)
	expect_equal(vblanks_in_two, VBLANKS_IN_SUB_STATE_2)
	expect_equal(last_timer, LAST_TIMER)
	expect_equal(flow.frame_vblanks(), 1, "the title's frames")


func test_start_leaves_the_movie_at_once() -> void:
	var flow := _flow()
	if flow == null:
		return
	for i in 10:
		flow.step(0, 0)
	expect_equal(flow.frame_vblanks(), ArcadeGameFlow.MOVIE_VBLANKS)
	flow.step(ArcadeGameFlow.START, 0)
	expect_equal(flow.state, ArcadeGameFlow.State.MATCH as int)
	expect_equal(flow.frame_vblanks(), 1)


func test_without_the_files_the_view_shows_nothing() -> void:
	var view := ArcadeMovieView.new()
	expect(not view.available())
	view.show_frame(10)
	expect(not view.playing)
	view.stop()
	view.free()
