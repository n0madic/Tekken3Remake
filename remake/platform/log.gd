class_name Log
extends RefCounted
## Messages of the app and the tools: info on standard output with its level, debug details only
## with Godot's `--verbose`, warnings and errors on Godot's warning and error channels (the script
## backtrace starts in this file: its next frame is the caller, which the test runner's
## ErrorCounter reports).


static func debug(message: String) -> void:
	if OS.is_stdout_verbose():
		print("[debug] " + message)


static func info(message: String) -> void:
	print("[info] " + message)


static func warning(message: String) -> void:
	push_warning(message)


static func error(message: String) -> void:
	push_error(message)
