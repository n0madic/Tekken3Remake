extends TestSuite
## The ROUND TIME option: 20–60 s count down; the sixth value (∞) sets the infinite-time flag
## (0x800958D4, FUN_800DAF2C) and the timer stands still.

const INFINITE := 5

var _content: FightContent


func _timer_after(round_time: int, frames: int) -> Vector2i:
	if _content == null:
		_content = FightContent.load_from(AssetCatalog.ROOT)
	var setup := FightSetup.new()
	setup.round_time = round_time
	var sim := FightSimulation.new(_content, setup, RuleSet.original())
	var start := -1
	for i in 600:
		sim.step(PackedInt32Array([0, 0]))
		if sim.fight.round_state == 1:
			if start < 0:
				start = sim.fight.timer
			frames -= 1
			if frames == 0:
				break
	return Vector2i(start, sim.fight.timer)


func test_infinite_time_stands_still() -> void:
	if not require(AssetCatalog.ROOT.path_join("tables/fight.json")):
		return
	var timed := _timer_after(2, 120)
	expect(timed.y < timed.x, "40 s counts down (%d → %d)" % [timed.x, timed.y])
	var infinite := _timer_after(INFINITE, 120)
	expect_equal(infinite.y, infinite.x, "∞ stands still")
