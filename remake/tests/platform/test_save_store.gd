extends TestSuite
## The save file: the progress round-trips byte for byte; a missing or damaged file loads nothing.

## One file per test: the runners may run the tests at the same time.
const PATH := "user://test_progress_%s.json"


func _store(path: String) -> SaveStore:
	var s := SaveStore.new()
	s.progress_path = path
	return s


func test_progress_round_trips() -> void:
	var path := PATH % "round_trip"
	var s := _store(path)
	var bytes := PackedByteArray()
	for i in GameProgress.SAVE_BLOCK + GameProgress.RECORDS_SIZE:
		bytes.append((i * 7) & 0xFF)
	expect_equal(s.save_progress(bytes), SaveStore.CARD_DONE)
	expect_equal(s.load_progress(), bytes)
	DirAccess.remove_absolute(path)


func test_missing_or_damaged_file_loads_nothing() -> void:
	var path := PATH % "damaged"
	var s := _store(path)
	DirAccess.remove_absolute(path)
	expect(s.load_progress().is_empty(), "missing file")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"save\": \"AAAA\"}")
	f.close()
	expect(s.load_progress().is_empty(), "short file")
	DirAccess.remove_absolute(path)


func test_write_goes_through_a_temporary_file() -> void:
	var path := PATH % "atomic"
	var s := _store(path)
	var first := PackedByteArray()
	first.resize(GameProgress.SAVE_BLOCK + GameProgress.RECORDS_SIZE)
	first.fill(1)
	expect_equal(s.save_progress(first), SaveStore.CARD_DONE)
	expect(not FileAccess.file_exists(path + SaveStore.TEMPORARY_SUFFIX), "no temporary file is left")
	# A write that cannot start (a directory holds the temporary name) keeps the previous save.
	DirAccess.make_dir_absolute(path + SaveStore.TEMPORARY_SUFFIX)
	var second := first.duplicate()
	second.fill(2)
	expect_equal(s.save_progress(second), SaveStore.CARD_ERROR, "the failed write is reported")
	expect_equal(s.load_progress(), first, "the previous save is intact")
	DirAccess.remove_absolute(path + SaveStore.TEMPORARY_SUFFIX)
	DirAccess.remove_absolute(path)


func _document(bytes_filled: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(GameProgress.SAVE_BLOCK + GameProgress.RECORDS_SIZE)
	bytes.fill(bytes_filled)
	return bytes


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Windows removes the old file before its rename: a write interrupted between the two leaves only
## the complete temporary file, and a partial temporary file never replaces a good save.
func test_an_interrupted_write_is_recovered() -> void:
	var path := PATH % "recovery"
	var temporary := path + SaveStore.TEMPORARY_SUFFIX
	var s := _store(path)
	DirAccess.remove_absolute(path)
	var newest := _document(2)
	expect_equal(s.save_progress(newest), SaveStore.CARD_DONE)
	var text := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(path)
	_put(temporary, text)
	expect_equal(s.load_progress(), newest, "only the complete temporary file is left")
	DirAccess.remove_absolute(temporary)
	expect_equal(s.save_progress(_document(1)), SaveStore.CARD_DONE)
	_put(temporary, text.substr(0, text.length() / 2))
	expect_equal(s.load_progress(), _document(1), "a partial temporary file leaves the save alone")
	DirAccess.remove_absolute(temporary)
	DirAccess.remove_absolute(path)


func test_settings_recover_the_same_way() -> void:
	var path := "user://test_settings_recovery.json"
	var store := SaveStore.new()
	store.settings_path = path
	DirAccess.remove_absolute(path)
	_put(path + SaveStore.TEMPORARY_SUFFIX, "{\"volume_music\": 3}")
	expect_equal(store.load_settings(), {"volume_music": 3.0}, "the complete temporary file")
	DirAccess.remove_absolute(path + SaveStore.TEMPORARY_SUFFIX)
	_put(path, "{\"volume_music\": 5}")
	_put(path + SaveStore.TEMPORARY_SUFFIX, "{\"volume_mus")
	expect_equal(store.load_settings(), {"volume_music": 5.0}, "a partial one is ignored")
	DirAccess.remove_absolute(path + SaveStore.TEMPORARY_SUFFIX)
	DirAccess.remove_absolute(path)
