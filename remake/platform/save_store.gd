class_name SaveStore
extends RefCounted
## The game's save files in place of the memory cards (remake-plan.md, M3): the save block and the
## records (GameProgress.save_data) in `user://progress.json` (card 1) or `progress2.json` (card 2,
## ProgressCard), and the remake's own settings
## (window, audio, input) in `user://settings.json`. The progress file keeps the bytes as the
## game's card file holds them, so a load restores exactly what was saved.

const PROGRESS_PATHS: Array[String] = ["user://progress.json", "user://progress2.json"]
const SETTINGS_PATH := "user://settings.json"
const VERSION := 1
const TEMPORARY_SUFFIX := ".tmp"
## The memory card results the options screen shows (menu_sim CardStub).
const CARD_DONE := 0
const CARD_ERROR := 5

var progress_path := PROGRESS_PATHS[0]
var settings_path := SETTINGS_PATH


## The saved progress, or an empty array when there is none (or it is unreadable). A complete
## temporary file of an interrupted write (see `_write`) is the newest save and is read first.
func load_progress() -> PackedByteArray:
	for path: String in _candidates(progress_path):
		var bytes := _read_progress(path)
		if not bytes.is_empty():
			return bytes
	return PackedByteArray()


## Writes the progress; returns a memory card result (0 done, 5 error).
func save_progress(bytes: PackedByteArray) -> int:
	var text := JSON.stringify({"version": VERSION, "save": Marshalls.raw_to_base64(bytes)}, "\t")
	return CARD_DONE if _write(progress_path, text) else CARD_ERROR


func load_settings() -> Dictionary:
	for path: String in _candidates(settings_path):
		var d: Variant = _parse(path)
		if d is Dictionary:
			return d
	return {}


func save_settings(settings: Dictionary) -> bool:
	return _write(settings_path, JSON.stringify(settings, "\t"))


## The files a document may be in, the newest first: the temporary file of a write that was
## interrupted before its rename (a partial one fails to parse and the loaders go on), then the file.
static func _candidates(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for candidate: String in [path + TEMPORARY_SUFFIX, path]:
		if FileAccess.file_exists(candidate):
			out.append(candidate)
	return out


## The JSON document in a file, or null when it does not parse (a write that was cut off).
static func _parse(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data


func _read_progress(path: String) -> PackedByteArray:
	var d: Variant = _parse(path)
	if not d is Dictionary:
		Log.warning("SaveStore: %s is not a progress file" % path)
		return PackedByteArray()
	var data: Dictionary = d
	if JsonFile.number(data.get("version", 0)) != VERSION or not data.has("save"):
		Log.warning("SaveStore: %s has an unknown version" % path)
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(str(data["save"]))
	if bytes.size() != GameProgress.SAVE_BLOCK + GameProgress.RECORDS_SIZE:
		Log.warning("SaveStore: %s has %d bytes" % [path, bytes.size()])
		return PackedByteArray()
	return bytes


## Writes `text` to a temporary file next to `path`, checks it by reading it back and renames it
## over `path`, so that an interrupted write (a kill, a power loss, Android suspending the app)
## leaves the previous file. Windows removes the old file before it renames: an interruption
## between the two leaves the complete temporary file, which the loaders read.
static func _write(path: String, text: String) -> bool:
	var temporary := path + TEMPORARY_SUFFIX
	var f := FileAccess.open(temporary, FileAccess.WRITE)
	if f == null:
		Log.warning("SaveStore: cannot write %s (%s)" % [temporary, error_string(FileAccess.get_open_error())])
		return false
	var stored := f.store_string(text)
	f.close()
	# store_string only reports the buffered write, close() the flush not at all.
	if not stored or FileAccess.get_file_as_string(temporary) != text:
		Log.warning("SaveStore: cannot write all of %s" % temporary)
		DirAccess.remove_absolute(temporary)
		return false
	var result := DirAccess.rename_absolute(temporary, path)
	if result != OK:
		Log.warning("SaveStore: cannot replace %s (%s)" % [path, error_string(result)])
		DirAccess.remove_absolute(temporary)
		return false
	return true
