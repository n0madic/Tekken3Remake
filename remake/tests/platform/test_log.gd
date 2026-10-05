extends TestSuite
## Errors raised through Log are reported at their caller: the test runner's ErrorCounter takes the
## first script frame outside platform/log.gd.


func test_error_position_is_the_script_frame() -> void:
	var at := ErrorCounter._script_position(Engine.capture_script_backtraces())
	expect(at.begins_with("test_log.gd:"), "the innermost script frame: %s" % at)
	expect(at.ends_with("test_error_position_is_the_script_frame"), "with its function")
	expect_equal(ErrorCounter._script_position([]), "", "no script backtrace")
