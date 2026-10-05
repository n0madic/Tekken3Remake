class_name FighterCompare
extends RefCounted
## Compares a FighterState with a fighter record of a fight trace, field by field: every scalar
## field of `tools/ghidra/fighter_fields.tsv` whose snake_case name (or alias) is a FighterState
## property, the move-row pointers as rows, and the world joints.

const JOINTS := 0x8F4
const JOINT_BYTES := 0x44
const JOINT_T := 0x14
const STALE_BANK := -3
const SKIPPED := ["reaction", "hitDone0", "hitDone1", "hitDone2", "hitDone3",
	"screenXCopy", "setupFlag128B", "bestHitSlot"]

var trace: RecordTrace
var fields: Array[Dictionary] = []    ## offset, type, name, property
var unmapped := PackedStringArray()


func _init(fight_trace: RecordTrace) -> void:
	trace = fight_trace
	var probe := FighterState.new()
	var props := {}
	for p in probe.get_property_list():
		props[p["name"]] = true
	for name: String in trace.field_types:
		var type: String = trace.field_types[name]
		if name in SKIPPED:
			continue
		var prop := _snake(name)
		if not props.has(prop):
			unmapped.append(name)
			continue
		fields.append({"offset": trace.field_offset(name), "type": type, "name": name, "property": prop})


static func _snake(name: String) -> String:
	var out := ""
	for i in name.length():
		var c := name[i]
		if c == c.to_upper() and c != c.to_lower() and i > 0:
			var prev := name[i - 1]
			if prev == prev.to_lower() or prev.is_valid_int():
				out += "_"
		out += c.to_lower()
	return out


## The differences of fighter `index` at `frame` as "name: actual ≠ expected" lines.
## `banks` maps the trace's bank index (player 0, player 1, common) to the remake's banks.
func differences(f: FighterState, frame: int, index: int, banks: Array[MotionBank]) -> PackedStringArray:
	var out := PackedStringArray()
	for d in fields:
		var offset: int = d["offset"]
		var type: String = d["type"]
		var prop: String = d["property"]
		var value: Variant = f.get(prop)
		if type == "void*":
			if value != null and not (value is MoveRow):
				continue
			var pointer := trace.fighter_u32(frame, index, offset)
			var actual := _row_key(value as MoveRow, banks)
			if actual.x == STALE_BANK:
				# A row of a bank that is no longer loaded (Mokujin's previous round): the game
				# still points to where that row was.
				var row := value as MoveRow
				if not pointer in trace.row_addresses(frame, row.bank.type_code, row.index):
					out.append("%s: stale row %d of %s ≠ 0x%08X" % [d["name"], row.index, row.bank.name, pointer])
				continue
			var expected := trace.row_of(frame, pointer)
			if actual != expected:
				out.append("%s: %s ≠ %s" % [d["name"], actual, expected])
			continue
		if not (value is int):
			continue
		var size := RecordTrace.signed_size(type)
		var expected_v := trace.read(trace.record(frame, index) + offset, size)
		var actual_v := RecordTrace.width(value as int, size)
		if actual_v != expected_v:
			out.append("%s: %d ≠ %d" % [d["name"], actual_v, expected_v])
	var h := f.hands
	var hands := {
		"hands current": [PackedInt32Array([Fx.s16(h.current[0]), Fx.s16(h.current[1])]), 0x127C, -2, 2],
		"hands target": [PackedInt32Array([Fx.s16(h.target[0]), Fx.s16(h.target[1])]), 0x1280, -2, 2],
		"hands rate": [PackedInt32Array([Fx.s16(h.rate[0]), Fx.s16(h.rate[1])]), 0x1284, -2, 2],
		"face speed": [PackedInt32Array([Fx.s16(h.face_speed)]), 0x128E, -2, 1],
		"face": [PackedInt32Array([h.face & 0xFF]), 0x1290, 1, 1],
		"ogre level": [PackedInt32Array([Fx.s16(h.ogre_level), Fx.s16(h.ogre_target), Fx.s16(h.ogre_rate)]), 0x1296, -2, 3],
		"wings": [PackedInt32Array([h.wing_frame & 0xFF, h.wing_phase & 0xFF, h.wing_first & 0xFF]), 0x128B, 1, 3],
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
		for k in FighterBody.JOINT_BLOCKS:
			var at := JOINTS + k * JOINT_BYTES + JOINT_T
			var expected_t := PackedInt32Array([trace.fighter_s32(frame, index, at),
				trace.fighter_s32(frame, index, at + 4), trace.fighter_s32(frame, index, at + 8)])
			if f.body.joints[k].t != expected_t:
				out.append("joint %d t: %s ≠ %s" % [k, f.body.joints[k].t, expected_t])
	return out


static func _row_key(row: MoveRow, banks: Array[MotionBank]) -> Vector2i:
	if row == null:
		return Vector2i(-1, -1)
	for b in banks.size():
		if banks[b] == row.bank:
			return Vector2i(b, row.index)
	return Vector2i(STALE_BANK, row.index)
