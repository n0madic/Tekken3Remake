extends TestSuite
## The attract demonstration without a performance (GameFlow.performance_factory returning null):
## the flow counts `performance_frames` frames instead, as the factory's documentation says.


func test_a_null_performance_counts_frames() -> void:
	var flow := imported_flow()
	if flow == null:
		return
	flow.performance_factory = func(_demo: int) -> EnbuPerformance: return null
	flow.performance_frames = 3
	flow.state = GameFlow.State.ENBU
	flow.sub = 1
	var idle := PackedInt32Array([0, 0])
	flow.step(idle)
	expect_equal(flow.sub, 2, "the performance's sub-state starts")
	expect(flow.performance == null, "without a performance")
	for i in 3:
		flow.step(idle)
	expect_equal(flow.sub, 3, "and ends after the counted frames")
