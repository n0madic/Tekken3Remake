extends TestSuite
## The converted motion banks: baked pose vectors equal the verified sampler's output in the
## traces for every frame, and move slots resolve through the common bank.

const BANK := "divmot00"
const COMMON := "divmot99"
const STANCE_SLOT := 3


func _bank(name: String) -> MotionBank:
	return MotionBank.load_named(AssetCatalog.ROOT + "motion", name)


func _inputs_present() -> bool:
	return require(AssetCatalog.ROOT + "motion/%s.json.gz" % BANK) \
		and require(TraceFiles.path("pose_%s.bin" % BANK), "run tools/research/export_traces.py first")


func test_baked_poses_match_traces() -> void:
	if not _inputs_present():
		return
	for name: String in [BANK, COMMON]:
		var bank := _bank(name)
		var anims := Traces.read_pose("pose_%s.bin" % name)
		# The common bank also bakes the streams the other banks' rows use.
		expect(bank.anims.size() >= anims.size(), name + " has every traced animation")
		var mismatches := 0
		for anim in anims:
			if not expect(bank.has_anim(anim.offset), "%s: missing stream %d" % [name, anim.offset]):
				continue
			expect_equal(bank.frame_count(anim.offset), anim.poses.size(), "%s stream %d frames" % [name, anim.offset])
			for f in anim.poses.size():
				if bank.pose(anim.offset, f) != anim.poses[f]:
					mismatches += 1
		expect_equal(mismatches, 0, name + " pose mismatches")


func test_frames_clamp_like_the_game() -> void:
	if not _inputs_present():
		return
	var bank := _bank(BANK)
	var offset: int = bank.anims.keys()[0]
	var last := bank.frame_count(offset) - 1
	expect_equal(bank.pose(offset, -5), bank.pose(offset, 0))
	expect_equal(bank.pose(offset, last + 10), bank.pose(offset, last))


func test_stance_slot_resolves() -> void:
	if not _inputs_present():
		return
	var motions := MotionSet.new(_bank(BANK), _bank(COMMON))
	var anim := motions.anim_for_slot(STANCE_SLOT)
	if expect(anim != null, "stance slot has no animation"):
		expect(anim.bank.has_anim(anim.value))
