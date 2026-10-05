class_name ErrorCounter
extends Logger
## Counts engine and script errors so the test runner can fail a test that hit a runtime
## error: GDScript aborts the failing function and continues in its caller, so without
## this a crashed test would look like a passing one.

const LOG_SCRIPT := "res://platform/log.gd"

var errors: PackedStringArray = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if not rationale.is_empty() else code
	var at := _script_position(script_backtraces)
	if at.is_empty():
		at = "%s:%d, %s" % [file.get_file(), line, function]
	_mutex.lock()
	errors.append("%s (%s)" % [text, at])
	_mutex.unlock()


## Where a script raised the error: its innermost frame outside `Log` (platform/log.gd reports
## for its callers), "" without a script backtrace.
static func _script_position(backtraces: Array[ScriptBacktrace]) -> String:
	for bt in backtraces:
		for i in bt.get_frame_count():
			var frame_file := bt.get_frame_file(i)
			if frame_file == LOG_SCRIPT:
				continue
			return "%s:%d, %s" % [frame_file.get_file(), bt.get_frame_line(i), bt.get_frame_function(i)]
	return ""


func take() -> PackedStringArray:
	_mutex.lock()
	var out := errors.duplicate()
	errors.clear()
	_mutex.unlock()
	return out
