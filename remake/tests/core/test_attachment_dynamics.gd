extends TestSuite
## AttachmentDynamics against the game's FUN_80037F10 run in the CPU harness on random
## fighter states (`work/traces/attachments.bin`, tools/research/attachment_cases.py).

const FILE := "attachments.bin"
const RECORD := 12
const JOINTS := 6          ## previous own joint, parent, joints 12, 15, 13, 16


func test_matches_the_game() -> void:
	if not require(TraceFiles.path(FILE), "run tools/research/export_traces.py first"):
		return
	if not require(AssetCatalog.ROOT + "tables/fighter.json"):
		return
	var tables := FighterTables.load_from(AssetCatalog.ROOT + "tables/fighter.json")
	var poses := PoseTables.load_from(AssetCatalog.ROOT + "tables/pose.json")
	var solver := PoseSolver.new(poses)
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(FILE))
	var count := data.decode_u32(8)
	var pos := 12
	var failed := 0
	for n in count:
		var slot := data.decode_u8(pos)
		var i := data.decode_u8(pos + 1)
		var started := data.decode_u8(pos + 2) != 0
		pos += 4
		var rest := Traces.s16s(data, pos, 3)
		pos += 6
		var record := Traces.s16s(data, pos, RECORD)
		pos += 2 * RECORD
		var frames: Array[JointFrame] = []
		for j in JOINTS:
			var rot := Traces.s16s(data, pos, 9)
			var t := PackedInt32Array([data.decode_s32(pos + 18), data.decode_s32(pos + 22), data.decode_s32(pos + 26)])
			frames.append(JointFrame.new(rot, t))
			pos += 30
		var offset := Traces.s16s(data, pos, 3)
		var want := Traces.s16s(data, pos + 6, 9)
		var want_yaw := data.decode_s32(pos + 24)
		var want_pitch := data.decode_s32(pos + 28)
		pos += 32
		var model := _model(slot, i, rest, record)
		var dyn := AttachmentDynamics.new(tables, poses, solver, model)
		dyn.started[i] = started
		var joints: Array[JointFrame] = []
		for j in CharacterModel.PART_COUNT:
			joints.append(JointFrame.new())
		joints[12] = frames[2]
		joints[15] = frames[3]
		joints[13] = frames[4]
		joints[16] = frames[5]
		var got := dyn.update(i, frames[1], frames[0], offset, joints)
		var ok := got == want
		if record[AttachmentDynamics.MODE] == AttachmentDynamics.MODE_TARGET and started:
			ok = ok and dyn.target_yaw == want_yaw and dyn.target_pitch == want_pitch
		if not ok:
			failed += 1
			if failed <= 5:
				expect(false, "case %d (slot 0x%x, attachment %d, record %s): expected %s, got %s" % [n, slot, i, record, want, got])
	expect_equal(failed, 0, "cases that differ of %d" % count)


static func _model(slot: int, i: int, rest: PackedInt32Array, record: PackedInt32Array) -> CharacterModel:
	var m := CharacterModel.new()
	m.costume_slot = slot
	for p in CharacterModel.PART_COUNT:
		var part := CharacterModel.Part.new()
		if p == AttachmentDynamics.FIRST_PART + i:
			part.rest = rest
			part.dynamics = record
		m.parts.append(part)
	return m
