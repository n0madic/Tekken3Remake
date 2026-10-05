class_name TraceFiles
## Where the golden traces are: `work/traces/` next to the project (`tools/research/export_traces.py`,
## `flow_trace.py`). They contain game-derived data and live outside the project and the
## repository. The `dev/` folder holds what reads them for the tests and `--replay`; exports leave
## it out.


static func directory() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../work/traces").simplify_path()


static func path(file: String) -> String:
	return directory().path_join(file)


static func exists(file: String) -> bool:
	return FileAccess.file_exists(path(file))
