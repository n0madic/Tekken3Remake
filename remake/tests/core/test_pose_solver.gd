extends TestSuite
## PoseSolver against the golden pose traces of the verified Python port (itself bit-exact
## with the game's PoseBuildMatrices in the CPU harness). Every frame of every animation of
## the banks is replayed with slots carried over, as while one move plays.

const TABLES := AssetCatalog.ROOT + "tables/pose.json"
const BANKS: Array[String] = ["divmot00", "divmot99"]


func test_pose_solver_matches_traces() -> void:
	if not require(TABLES) or not require(TraceFiles.path("pose_divmot00.bin"), "run tools/research/export_traces.py first"):
		return
	var solver := PoseSolver.new(PoseTables.load_from(TABLES))
	for bank in BANKS:
		var frames := 0
		var mismatches := 0
		var first_mismatch := ""
		for anim in Traces.read_pose("pose_%s.bin" % bank):
			var slots: Array[PackedInt32Array] = []
			for i in PoseSolver.SLOT_COUNT:
				slots.append(Fx.identity())
			for f in anim.poses.size():
				solver.build(anim.poses[f], slots)
				frames += 1
				var expected: Array = anim.slots[f]
				for s in PoseSolver.SLOT_COUNT:
					var want: PackedInt32Array = expected[s]
					if slots[s] != want:
						mismatches += 1
						if first_mismatch.is_empty():
							first_mismatch = "%s anim %d frame %d slot %d: %s != %s" % [bank, anim.offset, f, s, slots[s], want]
		expect(frames > 0, bank + ": no frames")
		expect_equal(mismatches, 0, "%s: %d frames, first mismatch %s" % [bank, frames, first_mismatch])
