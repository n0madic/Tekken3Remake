class_name ArcadeTrace
extends RecordTrace
## A fight trace of the arcade program (tools/research/arcade_fight_harness.py): per frame the pads,
## the game flow's sub-state before the frame and, after it, the `rand` state, both fighter records
## and the recorded RAM ranges.

const MAGIC := "T3AF"
const VERSION := 1
const FIELDS_FILE := "tools/ghidra/arcade_fighter_fields.tsv"
const FRAME_HEADER := 9
const SUB_STATE_AT := 4
const RAND_AT := 5
const ROWS := 0x80025E8C
const ROW_BYTES := 0x3C
const COUNT := 2

var _frame_size := 0
var _block_at := 0


static func path(scenario: String) -> String:
	return TraceFiles.directory().path_join("arcade_%s.bin" % scenario)


static func load_scenario(scenario: String) -> ArcadeTrace:
	var trace := ArcadeTrace.new()
	return trace if trace._load(FileAccess.get_file_as_bytes(path(scenario))) else null


func _load(data: PackedByteArray) -> bool:
	if not _unpack(data, MAGIC, VERSION):
		return false
	var block := _index_ranges()
	_block_at = FRAME_HEADER + COUNT * fighter_size
	_frame_size = _block_at + block
	return body.size() == _frame_size * frames


func _fields_file() -> String:
	return FIELDS_FILE


func record(frame: int, index: int) -> int:
	return frame * _frame_size + FRAME_HEADER + index * fighter_size


func pad(frame: int, player: int) -> int:
	return body.decode_u16(frame * _frame_size + 2 * player)


func sub_state(frame: int) -> int:
	return body.decode_s8(frame * _frame_size + SUB_STATE_AT)


func rand(frame: int) -> int:
	return body.decode_u32(frame * _frame_size + RAND_AT)


func has_ram(address: int, size: int) -> bool:
	return _range_of(address, size) >= 0


func ram(frame: int, address: int, size: int) -> int:
	return read(frame * _frame_size + _block_at + _range_of(address, absi(size)), size)


func row_addresses(_frame: int, _bank_type: int, index: int) -> PackedInt64Array:
	return PackedInt64Array([ROWS + index * ROW_BYTES])


## The arcade has one table of rows: bank 0, the row's number.
func row_of(_frame: int, pointer: int) -> Vector2i:
	if pointer == 0:
		return Vector2i(-1, -1)
	if pointer < ROWS or (pointer - ROWS) % ROW_BYTES != 0:
		return Vector2i(-2, pointer)
	return Vector2i(0, (pointer - ROWS) / ROW_BYTES)
