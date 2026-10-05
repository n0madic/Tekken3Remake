class_name Traces
## The pose and demonstration traces exported by `tools/research/export_traces.py` (found through
## TraceFiles).

const POSE_MAGIC := "T3PT"
const POSE_VERSION := 1
const POSE_CHANNELS := 49
const SLOTS := 18
const ENBU_MAGIC := "T3EB"
const ENBU_VERSION := 2
const ENBU_DONE := 1
const ENBU_ANIMATED := [2, 4]


## One animation of a pose trace: per frame the pose vector and the 18 slot rotations.
class PoseAnim:
	var offset: int
	var poses: Array[PackedInt32Array] = []
	var slots: Array[Array] = []        ## per frame: Array of 18 PackedInt32Array(9)


## One frame of a demonstration trace (`enbu_harness.py`): the game's state after the step.
class EnbuFrame:
	var phase: int
	var done: bool
	var animated: Array[bool] = []
	var script_frame: int
	var runner: Array[PackedInt32Array] = []     ## per fighter: state, costume, slot, end, frame
	var fighter: Array[PackedInt32Array] = []    ## poseFrame, rootFrame, prev, slot, key, charId
	var camera: PackedInt32Array                 ## pitch, yaw, x, y, z, H
	var fade: int
	var backdrop: PackedInt32Array               ## angle, last and this frame's yaw, point x, z
	var round_state: int                         ## the round state the harness runs with
	var calls: Array[PackedInt32Array] = []      ## kind, fighter, a, b, c, d


static func read_pose(file: String) -> Array[PoseAnim]:
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(file))
	var out: Array[PoseAnim] = []
	if data.slice(0, 4).get_string_from_ascii() != POSE_MAGIC or data.decode_u32(4) != POSE_VERSION:
		push_error("Traces: %s is not a version %d pose trace" % [file, POSE_VERSION])
		return out
	var count := data.decode_u32(8)
	var pos := 12
	for a in count:
		var anim := PoseAnim.new()
		anim.offset = data.decode_u32(pos)
		var frames := data.decode_u32(pos + 4)
		pos += 8
		for f in frames:
			var pose := PackedInt32Array()
			pose.resize(POSE_CHANNELS)
			for c in POSE_CHANNELS:
				pose[c] = data.decode_s16(pos + 2 * c)
			pos += 2 * POSE_CHANNELS
			var frame_slots := []
			for s in SLOTS:
				var m := PackedInt32Array()
				m.resize(9)
				for i in 9:
					m[i] = data.decode_s16(pos + 2 * i)
				pos += 18
				frame_slots.append(m)
			anim.poses.append(pose)
			anim.slots.append(frame_slots)
		out.append(anim)
	return out


static func read_enbu(file: String) -> Array[EnbuFrame]:
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(file))
	var out: Array[EnbuFrame] = []
	if data.slice(0, 4).get_string_from_ascii() != ENBU_MAGIC or data.decode_u32(4) != ENBU_VERSION:
		push_error("Traces: %s is not a version %d demonstration trace" % [file, ENBU_VERSION])
		return out
	var count := data.decode_u32(12)
	var round_state := data.decode_s32(16)
	var pos := 20
	for i in count:
		var f := EnbuFrame.new()
		f.phase = data.decode_u8(pos)
		var flags := data.decode_u8(pos + 1)
		f.done = flags & ENBU_DONE != 0
		for bit: int in ENBU_ANIMATED:
			f.animated.append(flags & bit != 0)
		f.script_frame = data.decode_s16(pos + 2)
		pos += 4
		for k in 2:
			f.runner.append(s16s(data, pos, 5))
			f.fighter.append(s16s(data, pos + 10, 6))
			pos += 22
		f.camera = PackedInt32Array([data.decode_s32(pos), data.decode_s32(pos + 4), data.decode_s32(pos + 8),
			data.decode_s32(pos + 12), data.decode_s32(pos + 16), data.decode_s16(pos + 20)])
		f.fade = data.decode_s16(pos + 22)
		f.backdrop = PackedInt32Array([data.decode_s32(pos + 24), data.decode_s32(pos + 28), data.decode_s32(pos + 32),
			data.decode_s32(pos + 36), data.decode_s32(pos + 40)])
		f.round_state = round_state
		var calls := data.decode_u8(pos + 44)
		pos += 45
		for c in calls:
			f.calls.append(PackedInt32Array([data.decode_u8(pos), data.decode_s8(pos + 1), data.decode_s16(pos + 2),
				data.decode_s16(pos + 4), data.decode_s16(pos + 6), data.decode_s16(pos + 8)]))
			pos += 10
		out.append(f)
	return out


static func s16s(data: PackedByteArray, pos: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = data.decode_s16(pos + 2 * i)
	return out
