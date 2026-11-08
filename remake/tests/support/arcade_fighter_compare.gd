class_name ArcadeFighterCompare
extends FighterCompare
## FighterCompare on the arcade's record: its hands and world joints are elsewhere.

const JOINT_T_AT := 0x75C
const JOINT_STRIDE := 0x50
const COMPARED_JOINTS := 18


func _body_differences(f: FighterState, frame: int, index: int) -> PackedStringArray:
	var out := PackedStringArray()
	var h := f.hands
	var hands := {
		"hands current": [PackedInt32Array([Fx.s16(h.current[0]), Fx.s16(h.current[1])]), 0x1164, -2, 2],
		"hands target": [PackedInt32Array([Fx.s16(h.target[0]), Fx.s16(h.target[1])]), 0x1168, -2, 2],
		"hands rate": [PackedInt32Array([Fx.s16(h.rate[0]), Fx.s16(h.rate[1])]), 0x116C, -2, 2],
		"face": [PackedInt32Array([Fx.s16(h.face)]), 0x1172, -2, 1],
		"face speed": [PackedInt32Array([Fx.s16(h.face_speed)]), 0x1174, -2, 1],
		"ogre level": [PackedInt32Array([Fx.s16(h.ogre_level), Fx.s16(h.ogre_target), Fx.s16(h.ogre_rate)]), 0x1178, -2, 3],
		"wings": [PackedInt32Array([h.wing_frame, h.wing_phase]), 0x115C, -4, 2],
	}
	for name: String in hands:
		var e: Array = hands[name]
		var actual: PackedInt32Array = e[0]
		var at: int = e[1]
		var size: int = e[2]
		var count: int = e[3]
		var expected := PackedInt32Array()
		for k in count:
			expected.append(trace.read(trace.record(frame, index) + at + k * absi(size), size))
		if actual != expected:
			out.append("%s: %s ≠ %s" % [name, actual, expected])
	if f.body != null:
		for k in COMPARED_JOINTS:
			var at := JOINT_T_AT + k * JOINT_STRIDE
			var expected_t := PackedInt32Array([trace.fighter_s32(frame, index, at),
				trace.fighter_s32(frame, index, at + 4), trace.fighter_s32(frame, index, at + 8)])
			if f.body.joints[k].t != expected_t:
				out.append("joint %d t: %s ≠ %s" % [k, f.body.joints[k].t, expected_t])
		for a: CharacterModel.ArcadeAttachment in f.body.model.arcade_attachments:
			var row := a.joint - CharacterModel.ARCADE_JOINT + ArcadeBody.FIRST_ROW
			var at := JOINT_T_AT + row * JOINT_STRIDE
			var expected_t := PackedInt32Array([trace.fighter_s32(frame, index, at),
				trace.fighter_s32(frame, index, at + 4), trace.fighter_s32(frame, index, at + 8)])
			if f.body.joints[row].t != expected_t:
				out.append("row %d t: %s ≠ %s" % [row, f.body.joints[row].t, expected_t])
	return out
