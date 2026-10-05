extends SceneTree
## Headless test runner:
##
##     godot --headless --path remake -s res://tests/run_tests.gd [-- [--quick] [--claim=<dir>] [--times=<file>]
##         [--times-out=<file>] <name filter>...]
##
## Finds every `test_*.gd` below res://tests, runs each `test_*` method of its TestSuite
## and exits with 0 when nothing failed, 1 otherwise. A test fails on a failed expectation
## or on any engine or script error logged while it runs. `--quick` leaves out the suites that
## declare `const SLOW := true` (the comparisons with the game's traces). With `--claim=<dir>`
## several runners share one run (tools/remake/run_tests.sh): each runs the tests it claims first
## in that directory, the longest first by the times of earlier runs (`--times=<file>`, lines
## `<path> <test>\t<ms>`), so the runners end close together; `--times-out=<file>` writes this
## runner's times.
##
## The run starts from the first process frame, not from `_init`: a runtime error aborts
## only the function it happens in, so an error inside `_run` still returns here and the
## runner quits with a failure instead of hanging. It quits AUDIO_DRAIN seconds later: the
## audio server releases a stopped playback on a later mix, and one still held at exit is
## reported as leaked.

const ROOT := "res://tests"
const AUDIO_DRAIN_MSEC := 200
## The settings file of this runner: the tests change the Settings autoload (and a test aborted by
## a runtime error leaves it changed), so it never writes the user's user://settings.json.
const SETTINGS_PATH := "user://test_runner_settings_%d.json"

var errors := ErrorCounter.new()
var started := false
var _exit_code := -1
var _quit_at := 0
var _claims := ""                    ## `--claim`: the directory the runners of a run claim tests in


func _initialize() -> void:
	OS.add_logger(errors)


func _process(_delta: float) -> bool:
	if started:
		if _exit_code >= 0 and Time.get_ticks_msec() >= _quit_at:
			_drop_settings()
			quit(_exit_code)
		return false
	started = true
	_isolate_settings()
	var result: Variant = _run()
	var leftover := errors.take()
	for message in leftover:
		print("ERROR  " + message)
	_exit_code = 1
	if result is int and leftover.is_empty():
		_exit_code = result
	_quit_at = Time.get_ticks_msec() + AUDIO_DRAIN_MSEC
	return false


## The Settings autoload, or null. This script compiles before the autoloads exist and must not
## name GameSettings, whose script needs them: the autoload is reached by its node.
func _settings() -> Node:
	return root.get_node_or_null(^"Settings")


func _isolate_settings() -> void:
	var settings := _settings()
	if settings != null:
		var store := settings.get("store") as SaveStore
		store.settings_path = SETTINGS_PATH % OS.get_process_id()


## The runner's settings file and what the tests left unsaved: nothing is written at exit.
func _drop_settings() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.set("_dirty", false)
	var path := (settings.get("store") as SaveStore).settings_path
	for file: String in [path, path + SaveStore.TEMPORARY_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


func _run() -> int:
	var filters := PackedStringArray()
	var quick := false
	var times_in := ""
	var times_out := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick":
			quick = true
		elif arg.begins_with("--claim="):
			_claims = arg.trim_prefix("--claim=")
		elif arg.begins_with("--times="):
			times_in = arg.trim_prefix("--times=")
		elif arg.begins_with("--times-out="):
			times_out = arg.trim_prefix("--times-out=")
		else:
			filters.append(arg)
	var passed := 0
	var failed := 0
	var skipped := 0
	var start := Time.get_ticks_msec()
	var suites: Dictionary = {}           # path → TestSuite
	var tests: Array[Array] = []          # [path, name, arguments]
	for path in _suites(ROOT):
		var script := load(path) as GDScript
		var load_errors := errors.take()
		if script == null or not script.can_instantiate() or not load_errors.is_empty():
			if _claim("load " + path):
				print("ERROR  %s does not compile" % path)
				for message in load_errors:
					print("         " + message)
				failed += 1
			continue
		if quick and script.get_script_constant_map().get("SLOW", false):
			continue
		var suite := script.new() as TestSuite
		if suite == null:
			if _claim("suite " + path):
				print("ERROR  %s does not extend TestSuite" % path)
				failed += 1
			continue
		suites[path] = suite
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if name.begins_with("test_") and _selected(path, name, filters):
				tests.append([path, name, method["args"]])
	if not _claims.is_empty():
		_longest_first(tests, _read_times(times_in))
	var times := PackedStringArray()
	for test: Array in tests:
		var path: String = test[0]
		var name: String = test[1]
		var args: Array = test[2]
		if not _claim(path + " " + name):
			continue
		if not args.is_empty():
			print("FAIL   %s::%s takes arguments; tests must take none" % [path.get_file(), name])
			failed += 1
			continue
		var suite: TestSuite = suites[path]
		suite.reset()
		var t := Time.get_ticks_msec()
		suite.call(name)
		var elapsed := Time.get_ticks_msec() - t
		times.append("%s %s\t%d" % [path, name, elapsed])
		for message in errors.take():
			suite.failures.append("runtime error: " + message)
		if not suite.failures.is_empty():
			failed += 1
			print("FAIL   %s::%s (%d ms)" % [path.get_file(), name, elapsed])
			for message in suite.failures:
				print("         " + message)
		elif not suite.skipped.is_empty():
			skipped += 1
			print("SKIP   %s::%s — %s" % [path.get_file(), name, suite.skipped])
		else:
			passed += 1
			print("ok     %s::%s (%d ms)" % [path.get_file(), name, elapsed])
	if not times_out.is_empty():
		var f := FileAccess.open(times_out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(times) + "\n")
	print("\n%d passed, %d failed, %d skipped in %.1f s" % [passed, failed, skipped, (Time.get_ticks_msec() - start) / 1000.0])
	return 1 if failed > 0 else 0


## The tests in the order runners sharing a run should take them: the longest of the last runs
## first, and tests without a time (new ones) before all of them.
static func _longest_first(tests: Array[Array], times: Dictionary) -> void:
	var keyed: Array[Array] = []
	for i in tests.size():
		var key := "%s %s" % [tests[i][0], tests[i][1]]
		var ms: int = times.get(key, 1 << 40)
		keyed.append([-ms, i, tests[i]])
	keyed.sort()
	for i in keyed.size():
		tests[i] = keyed[i][2]


## `--times`: lines `<path> <test>\t<ms>` of earlier runs.
static func _read_times(path: String) -> Dictionary:
	var out: Dictionary = {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var parts := line.split("\t")
		if parts.size() == 2:
			out[parts[0]] = parts[1].to_int()
	return out


## With `--claim=<dir>` (runners sharing a run): true for the one runner that creates the
## directory of `key` first (mkdir is atomic); without it, always true.
func _claim(key: String) -> bool:
	if _claims.is_empty():
		return true
	return DirAccess.make_dir_absolute(_claims.path_join(key.md5_text())) == OK


func _selected(path: String, name: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for f in filters:
		if f in path or f in name:
			return true
	return false


func _suites(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var subs := DirAccess.get_directories_at(dir)
	subs.sort()
	for sub in subs:
		out.append_array(_suites(dir.path_join(sub)))
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir.path_join(file))
	return out
