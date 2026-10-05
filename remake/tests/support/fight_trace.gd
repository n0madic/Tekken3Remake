class_name FightTrace
extends RecordTrace
## A fight trace (`tools/research/fight_harness.py`): the game's own fight run frame by frame in the
## CPU harness. Per frame: both pads, FightMain's sub-state before the frame, the engine calls
## logged during it, both fighter records and the recorded global RAM ranges after it.
##
## Fighter fields are read by the names of `tools/ghidra/fighter_fields.tsv` (fighter.md), globals
## by address. Pointers in the records (move rows) are turned into rows with `row_of`.

const MAGIC := "T3FT"
const VERSION := 2

var _frame_starts := PackedInt32Array()
var _record_starts := PackedInt32Array()       ## where the fighter records of a frame begin


static func path(scenario: String) -> String:
	return TraceFiles.path("fight_%s.bin" % scenario)


static func exists(scenario: String) -> bool:
	return FileAccess.file_exists(path(scenario))


static func load_scenario(scenario: String) -> FightTrace:
	var t := FightTrace.new()
	if not t._unpack(FileAccess.get_file_as_bytes(path(scenario)), MAGIC, VERSION):
		push_error("FightTrace: %s is not a version %d fight trace" % [scenario, VERSION])
		return null
	t._index()
	return t


func _index() -> void:
	var range_bytes := _index_ranges()
	var pos := 0
	for f in frames:
		_frame_starts.append(pos)
		pos += 6 + _calls_size(pos + 6, body.decode_u8(pos + 5))
		_record_starts.append(pos)
		pos += 2 * fighter_size + range_bytes


# ---- per frame ----------------------------------------------------------------------------

func pad(frame: int, player: int) -> int:
	return body.decode_u16(_frame_starts[frame] + 2 * player)


func sub_state(frame: int) -> int:
	return body.decode_s8(_frame_starts[frame] + 4)


## The frame's engine calls as (kind name, arguments…) arrays.
func calls(frame: int) -> Array[Array]:
	return _calls_at(_frame_starts[frame] + 6, body.decode_u8(_frame_starts[frame] + 5))


## Offset of fighter `index`'s record of a frame in `body`.
func record(frame: int, index: int) -> int:
	return _record_starts[frame] + index * fighter_size


## A global of the recorded RAM ranges (size 1, 2 or 4; negative: signed).
func ram(frame: int, address: int, size: int) -> int:
	var at := _range_of(address, absi(size))
	if at < 0:
		push_error("FightTrace: %x is not recorded" % (address & 0xFFFFFFFF))
		return 0
	return read(_record_starts[frame] + 2 * fighter_size + at, size)


func has_ram(address: int, size: int) -> bool:
	return _range_of(address, absi(size)) >= 0
