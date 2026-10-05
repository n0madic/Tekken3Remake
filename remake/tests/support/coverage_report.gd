extends SceneTree
## Checks every fight stage's view coverage (remake-plan.md#aspect-ratios) with the cameras of
## the fight traces: each frame's camera is placed by the CameraRig for a tall (9:19.5) window,
## grouped by camera kind (fight, throw and stream, hit, round end, replay), and the report gives
## per stage and kind how much of the upward extension the backdrop allows on average and at
## least, how often none, and how often it jumps between frames by more than a tenth (visible
## as the frame moving). The downward extension over the floor and the wide (Hor+) extension up
## to 21:9 need no coverage.
##
##     godot --headless --path remake -s res://tests/support/coverage_report.gd

## The report is loaded and run from the first process frame, like tests/run_tests.gd: a main script
## is compiled before the autoloads exist, and the view classes it uses reach `Settings`.
const REPORT := "res://tests/support/coverage_check.gd"

var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		var report: Object = (load(REPORT) as GDScript).new()
		report.call("run")
		quit(0)
	return false
