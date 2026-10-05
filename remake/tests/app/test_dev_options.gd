extends TestSuite
## The development options (DevOptions): the screenshot frame is drawn at its step, not between
## two steps, and `--graphics=` sets the session's preset.


func test_screenshot_frame_is_not_interpolated() -> void:
	var o := DevOptions.parse(PackedStringArray(["--screenshot=shot.png", "--frames=3"]))
	expect(o.screenshot_due(3) and not o.screenshot_due(2), "the screenshot's step")
	expect_equal(o.weight(0.25), 0.25, "frames between steps before it")
	o.capturing = true
	expect_equal(o.weight(0.25), 1.0, "the step itself once it is reached")


func test_screenshot_frame_has_a_default() -> void:
	var o := DevOptions.parse(PackedStringArray(["--screenshot=shot.png"]))
	expect(o.screenshot_due(DevOptions.DEFAULT_FRAMES), "without --frames")
	var first := DevOptions.parse(PackedStringArray(["--screenshot=shot.png", "--frames=0"]))
	expect(first.screenshot_due(1), "the first step is the earliest frame to save")


func test_a_bad_frame_count_keeps_the_default() -> void:
	var o := DevOptions.parse(PackedStringArray(["--screenshot=shot.png", "--frames=abc"]))
	expect(o.screenshot_due(DevOptions.DEFAULT_FRAMES), "not a number: the default")
	var empty := DevOptions.parse(PackedStringArray(["--screenshot=shot.png", "--frames="]))
	expect(empty.screenshot_due(DevOptions.DEFAULT_FRAMES), "empty: the default")
	var negative := DevOptions.parse(PackedStringArray(["--screenshot=shot.png", "--frames=-4"]))
	expect(negative.screenshot_due(1), "below the first step: the first")


func test_graphics_preset_for_the_session() -> void:
	var offered := str(Settings.choices("graphics")[1])
	DevOptions.parse(PackedStringArray(["--graphics=" + offered]))
	expect_equal(Settings.session.get("graphics"), offered, "kept for the session")
	Settings.session.erase("graphics")
	DevOptions.parse(PackedStringArray(["--graphics=nonsense"]))
	expect(not Settings.session.has("graphics"), "not a preset of this renderer: ignored")


func test_shading_for_the_session() -> void:
	DevOptions.parse(PackedStringArray(["--shading=curved"]))
	expect_equal(Settings.session.get("shading"), "curved", "kept for the session")
	Settings.session.erase("shading")
	DevOptions.parse(PackedStringArray(["--shading=curve"]))
	expect(not Settings.session.has("shading"), "not a choice: ignored")
