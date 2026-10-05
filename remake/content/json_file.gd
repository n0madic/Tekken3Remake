class_name JsonFile
## Reads JSON documents from the asset folder (gzip-compressed ones end in `.gz`).


static func read(path: String) -> Variant:
	var text := DataFile.read(path).get_string_from_utf8() if path.ends_with(".gz") else FileAccess.get_file_as_string(path)
	if text.is_empty():
		Log.error("JsonFile: cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var value: Variant = JSON.parse_string(text)
	if value == null:
		Log.error("JsonFile: invalid JSON in %s" % path)
		return {}
	return value


## A JSON array of numbers as PackedInt32Array (JSON numbers arrive as floats). Unsigned 32-bit
## words keep their bits (the conversion alone saturates them at 0x7FFFFFFF).
static func ints(value: Variant) -> PackedInt32Array:
	var items: Array = value if value is Array else []
	var out := PackedInt32Array(items)
	if items.is_empty() or number(items.max()) <= 0x7FFFFFFF:
		return out
	for i in items.size():
		var v := number(items[i])
		out[i] = v - 0x100000000 if v > 0x7FFFFFFF else v
	return out


## A JSON number as int (0 when it is not a number).
static func number(value: Variant) -> int:
	if value is float:
		var f: float = value
		return roundi(f)
	if value is int:
		var i: int = value
		return i
	return 0
