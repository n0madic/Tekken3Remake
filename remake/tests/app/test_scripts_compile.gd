extends TestSuite
## Every project script compiles with the project's strict typing (warnings are errors), not only
## the ones the other suites load: a scene script that fails to compile would break the build.

const SKIPPED := ["res://imported", "res://export", "res://.godot"]


func test_every_script_compiles() -> void:
	var paths := _scripts("res://")
	expect(paths.size() > 0, "no scripts found")
	for path in paths:
		var script := load(path) as GDScript
		expect(script != null and script.can_instantiate(), "%s does not compile" % path)


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if dir.trim_suffix("/") in SKIPPED:
		return out
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	return out
