extends TestSuite
## ArcadeAttachments against the arcade's FUN_8019b6d8 run in the CPU harness on random fighter
## states (`work/traces/arcade_attachments.bin`, tools/research/arcade_attachment_cases.py).

const FILE := "arcade_attachments.bin"
const RECORD := 16
const ROWS := 24


func test_matches_the_arcade() -> void:
	if not require(TraceFiles.path(FILE), "run tools/research/arcade_attachment_cases.py first"):
		return
	if not require(Assets.path(ArcadeAttachments.TABLES_FILE), "convert with --arcade first"):
		return
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(FILE))
	var count := data.decode_u32(8)
	var pos := 12
	var failed := 0
	for n in count:
		var slot := data.decode_u8(pos)
		var i := data.decode_u8(pos + 1)
		var started := data.decode_u8(pos + 2) != 0
		var parent := data.decode_u8(pos + 3)
		pos += 4
		var angles := Traces.s16s(data, pos, 3)
		pos += 6
		var record := Traces.s16s(data, pos, RECORD)
		pos += 2 * RECORD
		var wind := Traces.s16s(data, pos, 3)
		pos += 6
		var tip := _s32s(data, pos, 3)
		var target := _s32s(data, pos + 12, 2)
		var offset := _s32s(data, pos + 20, 3)
		pos += 32
		var joints: Array[JointFrame] = []
		joints.resize(CharacterModel.JOINT_COUNT)
		for row in ROWS:
			var rot := Traces.s16s(data, pos, 9)
			joints[ArcadeAttachments.joint_of_row(row)] = JointFrame.new(rot, _s32s(data, pos + 18, 3))
			pos += 30
		var want := Traces.s16s(data, pos, 9)
		var want_tip := _s32s(data, pos + 18, 3)
		var want_target := _s32s(data, pos + 30, 2)
		pos += 38
		var model := CharacterModel.new()
		model.costume_slot = slot
		var a := ArcadeAttachments.new(model)
		a.wind = wind
		a._tips[i] = tip
		a._target_yaw = target[0]
		a._target_pitch = target[1]
		var got: PackedInt32Array
		if slot in ArcadeAttachments.REST_ONLY_SLOTS and i < ArcadeAttachments.REST_ONLY_COUNT:
			got = Fx.identity()
		elif not started:
			got = ArcadeAttachments.solver().euler_to_matrix(angles[0], angles[1], angles[2])
		else:
			var own := joints[CharacterModel.ARCADE_JOINT + i]
			got = a.swing(slot, i, angles, record, own, joints[ArcadeAttachments.joint_of_row(parent)], offset, joints)
		var ok := got == want
		if started and not (slot in ArcadeAttachments.REST_ONLY_SLOTS and i < ArcadeAttachments.REST_ONLY_COUNT):
			ok = ok and a._tips[i] == want_tip and PackedInt32Array([a._target_yaw, a._target_pitch]) == want_target
		if not ok:
			failed += 1
			if failed <= 5:
				expect(false, "case %d (slot 0x%x, attachment %d, mode %d): expected %s tip %s target %s, got %s tip %s target %s"
					% [n, slot, i, record[ArcadeAttachments.MODE], want, want_tip, want_target, got, a._tips[i],
						[a._target_yaw, a._target_pitch]])
	expect_equal(failed, 0, "cases that differ of %d" % count)


static func _s32s(data: PackedByteArray, pos: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in count:
		out.append(data.decode_s32(pos + 4 * k))
	return out


## FUN_801e6acc / FUN_8019c738: still air off the helicopter stage; there, one of eight
## directions gusting with a period of 16 steps, normalised to about 4096.
func test_wind_blows_on_the_helicopter_stage_only() -> void:
	if not require(Assets.path("tables/fighter.json")):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var wind := ArcadeWind.new()
	wind.start(0, rng)
	wind.step()
	expect_equal(wind.vector, PackedInt32Array([0, 0, 0]), "still air on stage 0")
	wind.start(ArcadeWind.STAGE, rng)
	var gusts: Array[PackedInt32Array] = []
	for i in 32:
		wind.step()
		gusts.append(wind.vector)
	var v := gusts[0]
	var length := sqrt(float(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]))
	expect(absf(length - 4096.0) < 64.0, "normalised: %f" % length)
	expect(v[0] != 0 or v[2] != 0, "blowing sideways")
	expect_equal(gusts[16], gusts[0], "a period of 16 steps")


## ArcadeAttachments.update on the converted models against whole runs of the arcade's loop
## (FUN_8019b6d8 then CompMatrix for every drawn attachment in row order, FUN_80198754) on a
## skeleton turning step by step (`work/traces/arcade_attachment_steps.bin`).
func test_runs_match_the_arcade() -> void:
	const RUNS := "arcade_attachment_steps.bin"
	if not require(TraceFiles.path(RUNS), "run tools/research/arcade_attachment_cases.py first"):
		return
	if not require(Assets.path(ArcadeAttachments.TABLES_FILE), "convert with --arcade first"):
		return
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(RUNS))
	var count := data.decode_u32(8)
	var steps := data.decode_u32(12)
	var pos := 16
	var failed := 0
	var compared := 0
	for n in count:
		var slot := data.decode_u8(pos)
		var wind := Traces.s16s(data, pos + 2, 3)
		pos += 8
		var model := CharacterModel.load_from(AssetCatalog.ROOT + "characters/costume_%02d" % slot)
		var a := ArcadeAttachments.new(model)
		a.wind = wind
		for step in steps:
			var body: Array[JointFrame] = []
			for k in CharacterModel.PART_COUNT:
				body.append(_frame(data, pos) if k < ArcadeAttachments.FIRST_ATTACHMENT_ROW else JointFrame.new())
				if k < ArcadeAttachments.FIRST_ATTACHMENT_ROW:
					pos += 30
			var all := a.update(body)
			for i in CharacterModel.JOINT_COUNT - CharacterModel.ARCADE_JOINT:
				var want := _frame(data, pos)
				pos += 30
				var joint := CharacterModel.ARCADE_JOINT + i
				if not model.arcade_attachments.any(func(at: CharacterModel.ArcadeAttachment) -> bool: return at.joint == joint):
					continue
				compared += 1
				if all[joint].rot != want.rot or all[joint].t != want.t:
					failed += 1
					if failed <= 5:
						expect(false, "run %d (slot %d) step %d joint %d: expected %s %s, got %s %s"
							% [n, slot, step, joint, want.rot, want.t, all[joint].rot, all[joint].t])
	expect(compared > 0, "%d attachment joints compared" % compared)
	expect_equal(failed, 0, "attachment joints that differ in %d runs of %d steps" % [count, steps])


static func _frame(data: PackedByteArray, pos: int) -> JointFrame:
	return JointFrame.new(Traces.s16s(data, pos, 9), _s32s(data, pos + 18, 3))
