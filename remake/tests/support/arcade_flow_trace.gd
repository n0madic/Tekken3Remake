class_name ArcadeFlowTrace
extends RecordTrace
## A whole-game trace of the arcade program (tools/research/arcade_flow_trace.py): per frame the
## pads, the game state and sub-state, the `rand` state and the recorded RAM ranges.

const MAGIC := "T3AG"
const VERSION := 1
const FRAME_HEADER := 12
const STATE_AT := 4
const SUB_AT := 6
const RAND_AT := 8

var _frame_size := 0


static func path(scenario: String) -> String:
	return TraceFiles.directory().path_join("arcade_flow_%s.bin" % scenario)


static func load_scenario(scenario: String) -> ArcadeFlowTrace:
	var trace := ArcadeFlowTrace.new()
	return trace if trace._load(FileAccess.get_file_as_bytes(path(scenario))) else null


func _load(data: PackedByteArray) -> bool:
	if not _unpack(data, MAGIC, VERSION):
		return false
	_frame_size = FRAME_HEADER + _index_ranges()
	return body.size() == _frame_size * frames


func pad(frame: int, player: int) -> int:
	return body.decode_u16(frame * _frame_size + 2 * player)


func state(frame: int) -> int:
	return body.decode_u16(frame * _frame_size + STATE_AT)


func sub_state(frame: int) -> int:
	return body.decode_u16(frame * _frame_size + SUB_AT)


func rand(frame: int) -> int:
	return body.decode_u32(frame * _frame_size + RAND_AT)


func ram(frame: int, address: int, size: int) -> int:
	return read(frame * _frame_size + FRAME_HEADER + _range_of(address, absi(size)), size)
