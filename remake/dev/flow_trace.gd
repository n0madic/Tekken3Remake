class_name FlowTrace
extends RecordTrace
## A game flow trace (`tools/research/flow_trace.py`): the whole game run in the CPU harness from boot.
## Per frame: both pads, the game state and sub-state after the frame, the engine calls, the
## recorded RAM ranges, the blocks read through pointers (the Tekken Ball ball) and, in the fight
## state, the fighter records (a third one in Tekken Ball and Tekken Force). The header adds the
## motion banks' epochs (full fighter comparisons) and the progress pokes.

const MAGIC := "T3GF"
const VERSION := 2

var pointed: Dictionary = {}                   ## name → Vector2i(offset in the pointed block, size)
var _frame_starts := PackedInt32Array()
var _range_starts := PackedInt32Array()
var _pointed_starts := PackedInt32Array()
var _fighter_starts := PackedInt32Array()      ## −1 when the frame has no fighter records
var _fighter_counts := PackedByteArray()


static func path(scenario: String) -> String:
	return TraceFiles.path("flow_%s.bin" % scenario)


static func exists(scenario: String) -> bool:
	return FileAccess.file_exists(path(scenario))


static func load_scenario(scenario: String) -> FlowTrace:
	var t := FlowTrace.new()
	if not t._unpack(FileAccess.get_file_as_bytes(path(scenario)), MAGIC, VERSION):
		push_error("FlowTrace: %s is not a version %d flow trace" % [scenario, VERSION])
		return null
	t._index()
	return t


func _index() -> void:
	var range_bytes := _index_ranges()
	var pointed_bytes := 0
	for p: Array in header.get("pointed", []):
		var size: int = p[2]
		pointed[p[0] as String] = Vector2i(pointed_bytes, size)
		pointed_bytes += size
	var pos := 0
	for f in frames:
		_frame_starts.append(pos)
		pos += 9 + _calls_size(pos + 9, body.decode_u8(pos + 8))
		_range_starts.append(pos)
		pos += range_bytes
		_pointed_starts.append(pos)
		pos += pointed_bytes
		var fighters := body.decode_u8(pos)
		pos += 1
		_fighter_starts.append(pos if fighters != 0 else -1)
		_fighter_counts.append(fighters)
		pos += fighters * fighter_size


func pad(frame: int, player: int) -> int:
	return body.decode_u16(_frame_starts[frame] + 2 * player)


func state(frame: int) -> int:
	return body.decode_u16(_frame_starts[frame] + 4)


func sub_state(frame: int) -> int:
	return body.decode_u16(_frame_starts[frame] + 6)


## The frame's engine calls as (kind name, arguments…) arrays.
func calls(frame: int) -> Array[Array]:
	return _calls_at(_frame_starts[frame] + 9, body.decode_u8(_frame_starts[frame] + 8))


## A global of the recorded ranges (size 1, 2 or 4; negative: signed).
func ram(frame: int, address: int, size: int) -> int:
	var at := _range_of(address, absi(size))
	if at < 0:
		push_error("FlowTrace: %x is not recorded" % (address & 0xFFFFFFFF))
		return 0
	return read(_range_starts[frame] + at, size)


## Whether the trace records `address` (older traces lack the later screens' ranges).
func has_range(address: int) -> bool:
	return _range_of(address, 1) >= 0


## The bytes of a recorded block.
func block(frame: int, address: int, size: int) -> PackedByteArray:
	var at := _range_of(address, size)
	if at < 0:
		push_error("FlowTrace: %x is not recorded" % (address & 0xFFFFFFFF))
		return PackedByteArray()
	return body.slice(_range_starts[frame] + at, _range_starts[frame] + at + size)


func has_fighters(frame: int) -> bool:
	return _fighter_starts[frame] >= 0


## The number of fighter records of a frame (0 outside fights; 3 in Tekken Ball and Tekken Force).
func fighter_count(frame: int) -> int:
	return _fighter_counts[frame]


func record(frame: int, index: int) -> int:
	return _fighter_starts[frame] + index * fighter_size


func fighter(frame: int, index: int, offset: int, size: int) -> int:
	return read(record(frame, index) + offset, size)


func has_pointed(name: String) -> bool:
	return pointed.has(name)


## A value of a block read through a pointer (`pointed`), at `offset` in the block.
func pointed_value(frame: int, name: String, offset: int, size: int) -> int:
	var p: Vector2i = pointed[name]
	return read(_pointed_starts[frame] + p.x + offset, size)


## The progress pokes of the scenario: (address, byte) pairs written after boot.
func pokes() -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	for p: Array in header.get("pokes", []):
		out.append(PackedInt64Array([JsonFile.number(p[0]), JsonFile.number(p[1])]))
	return out
