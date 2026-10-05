extends TestSuite
## Gon's eyes' look direction (FighterAnimation.gon_gaze) against the game's GonEyesFollow run in
## the CPU harness on random head positions and rotations (`work/traces/gon_eyes.bin`,
## tools/research/gon_eyes_cases.py).

const FILE := "gon_eyes.bin"
const CASE := 46
const SHAPE_3_VALUE := 0x202            ## HandFaceCommand shape 3 on a hand channel


func test_matches_the_game() -> void:
	if not require(TraceFiles.path(FILE), "run tools/research/export_traces.py first"):
		return
	if not require(AssetCatalog.ROOT + "tables/camera.json"):
		return
	var tables := CameraTables.load_from(AssetCatalog.ROOT + "tables/camera.json")
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(FILE))
	var count := data.decode_u32(8)
	var failed := 0
	var seen := {}
	for n in count:
		var pos := 12 + CASE * n
		var rot := Traces.s16s(data, pos, 9)
		var own := _vector(data, pos + 18)
		var other := _vector(data, pos + 30)
		var want := data.decode_s32(pos + 42)
		var got := FighterAnimation.gon_gaze(rot, own, other, tables)
		seen[want] = true
		if got != want:
			failed += 1
			if failed <= 5:
				Log.info("case %d: shift %d, the game %d" % [n, got, want])
	expect_equal(failed, 0, "cases that differ of %d" % count)
	expect(seen.size() > 20, "the cases reach many shifts (%d)" % seen.size())
	expect(seen.has(17) and seen.has(-17) and seen.has(0), "both ends and the middle")


static func _vector(data: PackedByteArray, pos: int) -> PackedInt32Array:
	return PackedInt32Array([data.decode_s32(pos), data.decode_s32(pos + 4), data.decode_s32(pos + 8)])


## FUN_80034354 on a Gon whose move has flag 0x40000: under the overhead KO camera (0x800B08D4)
## it commands the jaw channel to shape 3 (tools/research/verify_gon_eyes.py runs the routine).
func test_gon_shuts_his_eyes_by_the_jaw_under_the_overhead_camera() -> void:
	if not require(AssetCatalog.ROOT + "tables/fighter.json"):
		return
	var fight := FightState.new(FightTables.load_from(AssetCatalog.ROOT + "tables"), RuleSet.new())
	var animation := FighterAnimation.new(fight)
	animation.camera = CameraDirector.new(fight)
	var f := fight.fighters[0]
	f.char_id = Character.GON
	var move := MoveRow.new()
	move.flags = MoveFlag.REACT_CHAIN
	f.pose_move = move
	animation._blink(f)
	expect_equal(f.hands.current[0], 0, "another camera: the jaw is left alone")
	animation.camera.overhead = 1
	animation._blink(f)
	expect_equal(f.hands.current[0], SHAPE_3_VALUE, "the overhead camera: shape 3")
	expect_equal(f.hands.target[0], SHAPE_3_VALUE, "held")
	f.hands = FighterHands.new()
	f.char_id = Character.PAUL
	animation._blink(f)
	expect_equal(f.hands.current[0], 0, "another character: not his jaw")
