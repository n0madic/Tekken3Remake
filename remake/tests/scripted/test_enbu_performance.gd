extends TestSuite
## The attract demonstration against the game's own FUN_800D3D64 run in the CPU harness
## (`work/traces/enbu_<n>.bin`, tools/research/enbu_harness.py): per frame the runner records, the
## fighters' frames and costumes, which fighters are animated, the frame events, the camera,
## the panorama's turn and the fade.

const STAGE := "stages/e"              ## the demonstration's stage 4


func _run(number: int) -> void:
	var file := "enbu_%d.bin" % number
	if not require(TraceFiles.path(file), "run tools/research/export_traces.py first"):
		return
	if not require(AssetCatalog.ROOT.path_join("enbu/enbu.json")):
		return
	var frames := Traces.read_enbu(file)
	var perf := EnbuAssets.load_from(AssetCatalog.ROOT).performance(number)
	if not frames.is_empty():
		perf.round_state = frames[0].round_state
	var box := _panorama_box(StageData.load_from(AssetCatalog.ROOT.path_join(STAGE)))
	var outside := 0
	for i in frames.size():
		var t := frames[i]
		var where := "demo %d frame %d" % [number, i]
		if not expect_equal(perf.phase, t.phase, where + " phase"):
			return
		if t.phase == EnbuPerformance.Phase.SCRIPT and not expect_equal(perf.frame, t.script_frame, where + " script frame"):
			return
		var done := perf.step()
		var ok := expect_equal(done, t.done, where + " end")
		for k in 2:
			var sf := perf.fighters[k]
			var f := sf.fighter
			var runner := PackedInt32Array([sf.state, sf.costume, sf.slot, sf.end_frame if t.runner[k][0] == 1 else t.runner[k][3], sf.frame])
			ok = expect_equal(runner, t.runner[k], where + " fighter %d runner" % k) and ok
			var fields := PackedInt32Array([f.pose_frame, f.root_frame, f.event_frame, f.costume_slot, f.costume_key, f.char_id])
			ok = expect_equal(fields, t.fighter[k], where + " fighter %d frames and costume" % k) and ok
			ok = expect_equal(sf.drawn, t.animated[k], where + " fighter %d animated" % k) and ok
		var c := perf.camera
		ok = expect_equal(PackedInt32Array([c.pitch, c.yaw, c.x, c.y, c.z, c.h]), t.camera, where + " camera") and ok
		if not box.has_point(Vector2(c.x, c.z)):
			outside += 1
		ok = expect_equal(perf.fade_drawn, t.fade, where + " fade") and ok
		var b := perf.backdrop
		ok = expect_equal(PackedInt32Array([b.angle, b.prev_yaw, b.yaw, b.point_x, b.point_z]), t.backdrop,
			where + " backdrop") and ok
		var expected: Array[PackedInt32Array] = []
		for call in t.calls:
			if call[1] >= 0:
				expected.append(call)
		ok = expect_equal(_calls(perf.events), expected, where + " events") and ok
		if not ok:
			return
	expect(perf.finished, "demo %d ends with the trace" % number)
	# The panorama is drawn from inside only (panorama.gdshader); EnbuView keeps it at the origin.
	expect_equal(outside, 0, "demo %d frames with the camera outside the panorama" % number)


## The panorama's horizontal box in world units (StageView: the objects scaled by 8).
static func _panorama_box(stage: StageData) -> Rect2:
	var e := stage.panorama_extent
	var k := StageView.PANORAMA_PARALLAX
	return Rect2(e[0] * k, e[2] * k, (e[1] - e[0]) * k, (e[3] - e[2]) * k)


static func _calls(events: SimEvents) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for e in events.items:
		match e.kind:
			SimEvents.Kind.EFFECT, SimEvents.Kind.SPARK:
				out.append(PackedInt32Array([e.kind, e.fighter, e.a, 0, 0, 0]))
			SimEvents.Kind.SHAKE_REQUEST:
				out.append(PackedInt32Array([SimEvents.Kind.SHAKE, e.fighter, e.a, 0, 0, 0]))
			SimEvents.Kind.FIGHTER_VIBRATE:
				# The trace logs FighterVibrate(fighter, kind).
				out.append(PackedInt32Array([SimEvents.Kind.VIBRATE, e.fighter, e.fighter, e.a, 0, 0]))
			SimEvents.Kind.DUST:
				out.append(PackedInt32Array([e.kind, e.fighter, 0, 0, 0, 0]))
			SimEvents.Kind.VIBRATE:
				out.append(PackedInt32Array([e.kind, e.fighter, e.a, e.b, 0, 0]))
			SimEvents.Kind.HAND:
				out.append(PackedInt32Array([e.kind, e.fighter, e.fighter, e.a, e.b, e.c]))
	return out


func test_demonstration_0_matches_the_game() -> void:
	_run(0)


func test_demonstration_1_matches_the_game() -> void:
	_run(1)


func test_demonstration_2_matches_the_game() -> void:
	_run(2)
