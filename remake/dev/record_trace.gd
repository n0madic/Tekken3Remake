class_name RecordTrace
extends RefCounted
## What fight and flow traces share: the file layout (magic, version, JSON header, deflated
## body), the engine calls and recorded RAM ranges of a frame, the raw fighter records of a
## frame, read by field name (`tools/ghidra/fighter_fields.tsv`) or offset, and the motion
## banks' epochs that turn the records' move-row pointers into rows (FighterCompare).

const FIELDS := "tools/ghidra/fighter_fields.tsv"
const MOVE_ROW_BYTES := 56
const SIZES := {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4, "void*": 4}

var header: Dictionary
var frames := 0
var body: PackedByteArray
var fighter_size := 0
var call_kinds: PackedStringArray
var ranges: Array[PackedInt64Array] = []       ## (address, size, offset in the frame's range block)
var field_types: Dictionary = {}               ## name → type of the fields file, in file order
var _fields: Dictionary = {}                   ## name → Vector2i(offset, size), negative size: signed


## Offset of fighter `index`'s record of a frame in `body`.
func record(_frame: int, _index: int) -> int:
	return -1


## Reads a trace file into `header` and `body`; false when it is not a `magic` trace of `version`.
func _unpack(data: PackedByteArray, magic: String, version: int) -> bool:
	if data.slice(0, 4).get_string_from_ascii() != magic or data.decode_u32(4) != version:
		return false
	var head_size := data.decode_u32(8)
	header = JSON.parse_string(data.slice(12, 12 + head_size).get_string_from_utf8())
	var pos := 12 + head_size
	var raw_size := data.decode_u32(pos)
	var packed_size := data.decode_u32(pos + 4)
	body = data.slice(pos + 8, pos + 8 + packed_size).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if body.size() != raw_size:
		return false
	frames = header["frames"]
	fighter_size = header["fighter_size"]
	var kinds: Array = header["call_kinds"]
	call_kinds = PackedStringArray(kinds)
	_read_fields()
	return true


## Indexes the header's recorded RAM ranges; returns the size of a frame's range block.
func _index_ranges() -> int:
	var offset := 0
	for r: Array in header["ranges"]:
		var size: int = r[2]
		var address: int = r[1]
		ranges.append(PackedInt64Array([address & 0xFFFFFFFF, size, offset]))
		offset += size
	return offset


## The size of a frame's `count` engine calls starting at `pos`.
func _calls_size(pos: int, count: int) -> int:
	var at := pos
	for c in count:
		at += 2 + 4 * body.decode_u8(at + 1)
	return at - pos


## `count` engine calls starting at `pos` as (kind name, arguments…) arrays.
func _calls_at(pos: int, count: int) -> Array[Array]:
	var out: Array[Array] = []
	for c in count:
		var entry: Array = [call_kinds[body.decode_u8(pos)]]
		var args := body.decode_u8(pos + 1)
		for a in args:
			entry.append(body.decode_s32(pos + 2 + 4 * a))
		out.append(entry)
		pos += 2 + 4 * args
	return out


## The offset of `address` in a frame's range block when a recorded range holds `size` bytes
## there, −1 otherwise.
func _range_of(address: int, size: int) -> int:
	address &= 0xFFFFFFFF
	for r in ranges:
		if address >= r[0] and address + size <= r[0] + r[1]:
			return r[2] + address - r[0]
	return -1


func _read_fields() -> void:
	var tsv := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../" + FIELDS))
	for line in tsv.split("\n"):
		if line.begins_with("#") or line.strip_edges().is_empty():
			continue
		var cols := line.split("\t")
		if not SIZES.has(cols[1]):
			continue
		field_types[cols[2]] = cols[1]
		_fields[cols[2]] = Vector2i(cols[0].hex_to_int(), signed_size(cols[1]))


## The byte size of a fields-file type, negative when signed.
static func signed_size(type: String) -> int:
	var size: int = SIZES[type]
	return -size if type.begins_with("s") else size


## `v` wrapped to a field of `size` bytes (negative: signed), as the trace records it.
static func width(v: int, size: int) -> int:
	match size:
		1:
			return v & 0xFF
		-1:
			return Fx.s8(v)
		2:
			return v & 0xFFFF
		-2:
			return Fx.s16(v)
		4:
			return v & 0xFFFFFFFF
	return Fx.w32(v)


func field_offset(name: String) -> int:
	var f: Vector2i = _fields[name]
	return f.x


## A named scalar field of a fighter record (fighter.md), sign-extended by its type.
func field(frame: int, index: int, name: String) -> int:
	var f: Vector2i = _fields[name]
	return read(record(frame, index) + f.x, f.y)


## Raw fighter record words at an offset.
func fighter_s32(frame: int, index: int, offset: int) -> int:
	return body.decode_s32(record(frame, index) + offset)


func fighter_u32(frame: int, index: int, offset: int) -> int:
	return body.decode_u32(record(frame, index) + offset)


func read(pos: int, size: int) -> int:
	match size:
		1: return body.decode_u8(pos)
		-1: return body.decode_s8(pos)
		2: return body.decode_u16(pos)
		-2: return body.decode_s16(pos)
		4: return body.decode_u32(pos)
		_: return body.decode_s32(pos)


# ---- pointers -----------------------------------------------------------------------------

## The addresses move row `index` of a bank of type `bank_type` had in the bank epochs up to
## `frame`: a row of a replaced bank (Mokujin's previous round) that the game still points to.
func row_addresses(frame: int, bank_type: int, index: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for epoch: Dictionary in header["bank_epochs"]:
		if JsonFile.number(epoch["frame"]) > frame:
			break
		for bank: Dictionary in epoch["banks"]:
			if JsonFile.number(bank["type"]) == bank_type:
				var sections: Array = bank["sections"]
				out.append(JsonFile.number(sections[1]) + index * MOVE_ROW_BYTES)
	return out


## The bank (0, 1: the fighters' own banks, 2: the common bank) and row of a move-row pointer
## in `frame`, Vector2i(-1, -1) for null.
func row_of(frame: int, pointer: int) -> Vector2i:
	if pointer == 0:
		return Vector2i(-1, -1)
	var banks: Array = []
	for epoch: Dictionary in header["bank_epochs"]:
		if JsonFile.number(epoch["frame"]) > frame:
			break
		banks = epoch["banks"]
	for b in banks.size():
		var sections: Array = banks[b]["sections"]
		var rows: int = sections[1]
		var rows_end: int = sections[2]
		if rows_end < rows:
			# The common bank has no move index: its section-2 pointer stays unrelocated.
			rows_end = sections[3]
		if pointer >= rows and pointer < rows_end:
			return Vector2i(b, (pointer - rows) / MOVE_ROW_BYTES)
	return Vector2i(-2, pointer)
