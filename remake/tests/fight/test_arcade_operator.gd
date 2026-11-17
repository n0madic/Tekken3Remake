extends TestSuite
## The operator's GAME OPTIONS (issue n0madic/Tekken3Remake#30) as the arcade build reads them: guard
## damage (0x8021FDA8, which FUN_8018BB68's guard branch tests) goes from the settings into a match,
## and a change made while a game is on waits until none is. The traces run with guard damage off.
## Needs a conversion from MAME's set alone; skipped otherwise.

const CHARS := [Character.PAUL, Character.LAW]

var _content: ArcadeFightContent
var _data: ArcadeFlowData


## A flow from the arcade conversion (its content loaded once), null (the test skipped) without one.
func _flow() -> ArcadeGameFlow:
	if not require(AssetCatalog.ROOT.path_join(ArcadeFlowData.FILE)):
		return null
	if not Assets.arcade_only():
		skip("not a conversion from the arcade set")
		return null
	if _content == null:
		_content = ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
		_data = ArcadeFlowData.load_from(AssetCatalog.ROOT.path_join(ArcadeFlowData.FILE))
	return ArcadeGameFlow.new(_content, _data, RuleSet.original(), ArcadeSettings.new(), 1)


func test_guard_damage_reaches_the_match() -> void:
	var flow := _flow()
	if flow == null:
		return
	flow.chars = PackedInt32Array(CHARS)
	for on: int in [0, 1]:
		flow.settings.guard_damage = on
		flow.match_flow._load()
		expect_equal(flow.fight.chip_damage, on, "the combat's chip damage (FUN_8018A44C's load)")


## The app's settings reach the flow when no game is on: the attract, the title, and the attract's
## demo fights and records pages (mode 6), from which Start begins a game; not during a game.
func test_a_change_waits_until_no_game_is_on() -> void:
	var flow := _flow()
	if flow == null:
		return
	var game := (load("res://app/arcade_game.gd") as GDScript).new() as Node
	game.set("flow", flow)
	var cases := [
		[ArcadeGameFlow.State.SELECT, ArcadeGameFlow.MODE_ARCADE, false],
		[ArcadeGameFlow.State.MATCH, ArcadeGameFlow.MODE_ARCADE, false],
		[ArcadeGameFlow.State.RANKING, ArcadeGameFlow.MODE_ARCADE, false],
		[ArcadeGameFlow.State.MATCH, ArcadeGameFlow.MODE_DEMO, true],
		[ArcadeGameFlow.State.RANKING, ArcadeGameFlow.MODE_DEMO, true],
		[ArcadeGameFlow.State.ATTRACT, ArcadeGameFlow.MODE_ARCADE, true],
		[ArcadeGameFlow.State.TITLE, ArcadeGameFlow.MODE_ARCADE, true],
	]
	for c: Array in cases:
		var at := "state %d, mode %d" % [c[0], c[1]]
		var before := flow.settings
		flow.state = c[0] as int
		flow.mode = c[1] as int
		game.set("_operator_changed", true)
		game.call("_apply_operator_settings")
		var read := c[2] as bool
		expect_equal(flow.settings != before, read, "%s: the settings read" % at)
		expect_equal(game.get("_operator_changed"), not read, "%s: the change still waiting" % at)
	game.free()
